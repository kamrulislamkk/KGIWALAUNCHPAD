// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Remix: compiler 0.8.28, EVM version cancun, optimizer ON (200 runs).
import {ERC20} from "@openzeppelin/contracts@5.6.1/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts@5.6.1/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts@5.6.1/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts@5.6.1/utils/ReentrancyGuard.sol";

/// @title LaunchToken
/// @notice v2.1 fixed-allocation token with launchpad-only burns and ETH dividend accounting.
/// @dev ETH remains in the launchpad. Transfers preserve earned dividends, not future entitlement.
contract LaunchToken is ERC20 {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000e18;
    uint256 public constant MAGNITUDE = 1 << 128;
    /// @dev Rewards are only distributed over at least this much circulating supply (1,000 tokens).
    /// A tiny denominator would blow up pointsPerShare and could overflow later transfers.
    uint256 public constant MIN_REWARD_SUPPLY = 1_000e18;
    address public immutable launchpad;
    uint256 public pointsPerShare;
    mapping(address => int256) public pointsCorrection;
    mapping(address => uint256) public withdrawn;

    error OnlyLaunchpad();
    error InvalidSupply();
    error InvalidAddress();
    error NoCirculatingSupply();
    error RewardOverflow();

    modifier onlyLaunchpad() {
        if (msg.sender != launchpad) revert OnlyLaunchpad();
        _;
    }

    /// @notice Mint exactly one billion tokens once to the deploying launchpad.
    /// @dev Constructor parameters are retained from v1; no subsequent mint path exists.
    constructor(string memory name, string memory symbol, uint256 supply, address mintTo)
        ERC20(name, symbol)
    {
        if (supply != TOTAL_SUPPLY) revert InvalidSupply();
        if (mintTo == address(0) || mintTo != msg.sender) revert InvalidAddress();
        launchpad = mintTo;
        _mint(mintTo, TOTAL_SUPPLY);
    }

    /// @notice Outstanding supply eligible for new rewards, excluding every launchpad-held token.
    function circulating() public view returns (uint256) {
        return totalSupply() - balanceOf(launchpad);
    }

    /// @notice Account for ETH already reserved by the launchpad, rounding down only.
    function addRewards(uint256 amount) external onlyLaunchpad {
        uint256 eligible = circulating();
        if (eligible < MIN_REWARD_SUPPLY) revert NoCirculatingSupply();
        pointsPerShare += Math.mulDiv(amount, MAGNITUDE, eligible);
    }

    /// @notice Unwithdrawn ETH entitlement; the excluded launchpad always has zero entitlement.
    function pendingRewards(address user) public view returns (uint256) {
        if (user == launchpad || user == address(0)) return 0;
        int256 corrected = _asInt(pointsPerShare * balanceOf(user)) + pointsCorrection[user];
        return uint256(corrected) / MAGNITUDE - withdrawn[user];
    }

    /// @notice Mark rewards consumed before returning their amount to the paying launchpad.
    function consumeRewards(address user) external onlyLaunchpad returns (uint256 owed) {
        owed = pendingRewards(user);
        withdrawn[user] += owed;
    }

    /// @notice Burn only from the launchpad's own inventory, never from a holder.
    function burn(uint256 amount) external onlyLaunchpad {
        _burn(launchpad, amount);
    }

    /// @dev Exclusion also covers unsold inventory and unclaimed fundraise allocations.
    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        int256 correction = _asInt(pointsPerShare * value);
        if (from != address(0) && from != launchpad) pointsCorrection[from] += correction;
        if (to != address(0) && to != launchpad) pointsCorrection[to] -= correction;
    }

    function _asInt(uint256 value) private pure returns (int256) {
        if (value > uint256(type(int256).max)) revert RewardOverflow();
        return int256(value);
    }
}

/// @title KgiwaLaunchpad
/// @notice v2.2 ETH exponential-curve launchpad, intended for GIWA Sepolia (91342).
/// @dev All curve costs and payouts use the same integer reserve function. No migrations or sweeps.
contract KgiwaLaunchpad is Ownable, ReentrancyGuard {
    uint256 private constant BPS = 10000;
    uint256 private constant UNIT = 1e18;
    uint256 private constant MIN_TRADE = 0.00001 ether;
    /// @dev 800M tradable on the curve plus 200M permanently locked in this contract = 1B total.
    uint256 private constant CURVE_SUPPLY = 800_000_000e18;
    uint256 private constant LOCKED = 200_000_000e18;
    uint256 private constant TOTAL_SUPPLY = CURVE_SUPPLY + LOCKED;
    uint256 private constant VIRTUAL_ETH = 5 ether;
    uint256 private constant VIRTUAL_TOKENS = 20_000_000e18;
    uint256 private constant P0 = VIRTUAL_ETH * UNIT / VIRTUAL_TOKENS;
    uint256 private constant K = 2302585092994045684;
    uint256 private constant A = P0 * (CURVE_SUPPLY / UNIT) * UNIT / K;
    uint256 private constant MAX_TARGET = 50 ether;
    /// @dev An unfilled fundraise stops accepting contributions after this long, and every
    /// contributor can then refund without needing the creator to cancel.
    uint256 private constant FUNDRAISE_DURATION = 30 days;
    // Original MIT implementation below uses 36-decimal intermediate series, not a new dependency.
    uint256 private constant HIGH = 1e36;
    uint256 private constant LN2_HIGH = 693147180559945309417232121458176568;

    struct TokenInfo {
        address creator;
        uint256 supply;
        uint256 price;
        uint256 curveInventory;
        uint256 reserveETH;
        uint256 volume;
        uint256 tradeFeeBps;
        bool launched;
    }

    struct ContributionInfo {
        uint256 ethContributed;
        uint256 tokensAllocated;
        bool claimed;
        bool refunded;
        uint256 claimedAmount;
    }

    struct Fundraise {
        address creator;
        string name;
        string symbol;
        string logoURI;
        uint256 supply;
        uint256 targetETH;
        uint256 raised;
        uint256 price;
        uint256 tradeFeeBps;
        uint8 status;
        address token;
        uint256 totalAllocated;
        uint256 sold;
        uint256 deadline;
        mapping(address => ContributionInfo) contributions;
        uint256 vestingHours;
        uint256 launchTime;
    }

    address public platformWallet;
    bool public paused;
    uint256 public instantCreationFee = 0.0001 ether;
    uint256 public fundraiseCreationFee = 0.05 ether;
    uint256 public totalVolume;
    mapping(address => TokenInfo) public tokens;
    mapping(address => string) public tokenLogoURI;
    mapping(address => uint256) public creatorFees;
    mapping(address => uint256) public holderPool;
    address[] private tokenList;
    address[] private traderList;
    mapping(address => bool) private isTrader;
    Fundraise[] private fundraiseList;

    error LaunchpadPaused();
    error InvalidAddress();
    error InvalidMetadata();
    error InvalidSupply();
    error InvalidFee();
    error InvalidPayment();
    error InvalidTarget();
    error InvalidFundraise();
    error InvalidStatus();
    error UnknownToken();
    error TradeTooSmall();
    error InsufficientInventory();
    error InsufficientReserve();
    error SlippageExceeded();
    error NothingToReceive();
    error AlreadyProcessed();
    error NotCreator();
    error ETHTransferFailed();
    error TokenTransferFailed();
    error RenounceDisabled();
    error CurveMathError();
    error FundraiseExpired();
    error InvalidVesting();

    event Trade(address indexed token, address indexed trader, bool isBuy, uint256 ethAmount, uint256 tokenAmount, uint256 fee, uint256 newPrice);
    event TokenCreated(address indexed token, address indexed creator, string name, string symbol);
    event FundraiseCreated(uint256 indexed fundraiseId, address indexed creator, uint256 targetETH);
    event Contribution(uint256 indexed fundraiseId, address indexed contributor, uint256 amount);
    event TokenLaunched(address indexed token, address indexed creator, uint256 price);
    event FundraiseCompleted(uint256 indexed fundraiseId, address indexed token);
    event FundraiseCancelled(uint256 indexed fundraiseId);
    event Claimed(uint256 indexed fundraiseId, address indexed user, uint256 tokenAmount);
    event Refunded(uint256 indexed fundraiseId, address indexed user, uint256 ethAmount);
    event FeesDistributed(address indexed token, uint256 platform, uint256 creator, uint256 holders, uint256 burned);
    event Burned(address indexed token, uint256 ethAmount, uint256 tokenAmount);
    event HolderRewardsClaimed(address indexed token, address indexed user, uint256 amount);
    event CreatorFeesClaimed(address indexed token, address indexed creator, uint256 amount);

    modifier whenNotPaused() {
        if (paused) revert LaunchpadPaused();
        _;
    }

    /// @notice Set the initial administrator and nonzero platform fee recipient.
    constructor(address initialOwner, address platformWallet_) Ownable(initialOwner) {
        if (platformWallet_ == address(0)) revert InvalidAddress();
        platformWallet = platformWallet_;
    }

    /// @notice Ownership can be transferred but never renounced, so a pause can always be lifted.
    function renounceOwnership() public view override onlyOwner {
        revert RenounceDisabled();
    }

    /// @notice Pause creation, trading, and contributions without blocking exits.
    function setPaused(bool value) external onlyOwner { paused = value; }

    /// @notice Change the recipient of subsequent platform fees.
    function setPlatformWallet(address wallet) external onlyOwner {
        if (wallet == address(0)) revert InvalidAddress();
        platformWallet = wallet;
    }

    /// @notice Set the ETH fee for subsequent instant launches.
    function setInstantCreationFee(uint256 fee) external onlyOwner { instantCreationFee = fee; }

    /// @notice Set the ETH fee for subsequent fundraise creations.
    function setFundraiseCreationFee(uint256 fee) external onlyOwner { fundraiseCreationFee = fee; }

    /// @notice Number of launched tokens, including completed fundraises.
    function tokenCount() external view returns (uint256) { return tokenList.length; }
    /// @notice Launched token at a zero-based index.
    function tokenAt(uint256 index) external view returns (address) { return tokenList[index]; }
    /// @notice Number of unique buyers and sellers.
    function traderCount() external view returns (uint256) { return traderList.length; }
    /// @notice Trader at a zero-based index.
    function traderAt(uint256 index) external view returns (address) { return traderList[index]; }
    /// @notice Number of fundraises, including launched and cancelled ones.
    function fundraiseCount() external view returns (uint256) { return fundraiseList.length; }

    /// @notice Return fundraise metadata; status is 0 active, 1 launched, 2 cancelled.
    function fundraises(uint256 id) external view returns (
        address creator, string memory name, string memory symbol, string memory logoURI,
        uint256 supply, uint256 targetETH, uint256 raised, uint256 price,
        uint256 tradeFeeBps, uint8 status, address token
    ) {
        Fundraise storage f = _fundraise(id);
        creator = f.creator;
        name = f.name;
        symbol = f.symbol;
        logoURI = f.logoURI;
        supply = f.supply;
        targetETH = f.targetETH;
        raised = f.raised;
        price = f.price;
        tradeFeeBps = f.tradeFeeBps;
        status = f.status;
        token = f.token;
    }

    /// @notice Return a user's cumulative allocation and settlement flags.
    function fundraiseContribution(uint256 id, address user) external view returns (
        uint256 ethContributed, uint256 tokensAllocated, bool claimed, bool refunded
    ) {
        ContributionInfo storage c = _fundraise(id).contributions[user];
        return (c.ethContributed, c.tokensAllocated, c.claimed, c.refunded);
    }

    /// @notice Return the vesting duration in hours and fill timestamp (zero before launch).
    function fundraiseVesting(uint256 id) external view returns (uint256 vestingHours, uint256 launchTime) {
        Fundraise storage f = _fundraise(id);
        return (f.vestingHours, f.launchTime);
    }

    /// @notice Return vested, unclaimed tokens; zero for a fundraise that has not launched.
    function claimableOf(uint256 id, address user) external view returns (uint256) {
        Fundraise storage f = _fundraise(id);
        if (f.status != 1) return 0;
        ContributionInfo storage c = f.contributions[user];
        return _vestedAllocation(f, c.tokensAllocated) - c.claimedAmount;
    }

    /// @notice Create a fixed-allocation token; excess ETH becomes the creator's first buy.
    function createInstant(
        string memory name, string memory symbol, string memory logoURI,
        uint256 supply, uint256 tradeFeeBps
    ) external payable nonReentrant whenNotPaused {
        _validate(name, symbol, logoURI, supply, tradeFeeBps);
        uint256 creationFee = instantCreationFee;
        if (msg.value < creationFee) revert InvalidPayment();
        address token = address(new LaunchToken(name, symbol, supply, address(this)));
        tokens[token] = TokenInfo(msg.sender, TOTAL_SUPPLY, P0, CURVE_SUPPLY, 0, 0, tradeFeeBps, true);
        tokenLogoURI[token] = logoURI;
        tokenList.push(token);
        emit TokenCreated(token, msg.sender, name, symbol);
        emit TokenLaunched(token, msg.sender, P0);
        uint256 remainder = msg.value - creationFee;
        if (remainder != 0) _buy(token, msg.sender, remainder, 0);
        _sendETH(platformWallet, creationFee);
    }

    /// @notice Buy along the exponential curve, with a minimum token output.
    function buy(address token, uint256 minimumTokensOut) external payable nonReentrant whenNotPaused {
        _buy(token, msg.sender, msg.value, minimumTokensOut);
    }

    /// @notice Quote buyer tokens after fees; over-capacity purchases revert rather than partially fill.
    function quoteBuy(address token, uint256 ethAmount) external view returns (uint256 tokensOut) {
        (tokensOut,,) = quoteBuyDetail(token, ethAmount);
    }

    /// @notice Quote net tokens, total fee and marginal price immediately after the main buy.
    /// @dev The returned price excludes the subsequent fee-funded burn purchase.
    function quoteBuyDetail(address token, uint256 ethAmount)
        public view returns (uint256 tokensOut, uint256 fee, uint256 newPrice)
    {
        TokenInfo storage t = _token(token);
        fee = Math.mulDiv(ethAmount, t.tradeFeeBps, BPS);
        uint256 sold = CURVE_SUPPLY - t.curveInventory;
        uint256 next = _buyPosition(sold, ethAmount - fee);
        return (next - sold, fee, _price(next));
    }

    /// @notice Sell approved tokens for the exact reserve-function difference, without a reserve cap.
    function sell(address token, uint256 tokenAmount, uint256 minimumETHOut)
        external nonReentrant whenNotPaused
    {
        TokenInfo storage t = _token(token);
        if (tokenAmount == 0) revert TradeTooSmall();
        (uint256 ethOut, uint256 fee,) = quoteSellDetail(token, tokenAmount);
        uint256 gross = ethOut + fee;
        if (ethOut == 0) revert NothingToReceive();
        if (gross < Math.min(MIN_TRADE, t.reserveETH)) revert TradeTooSmall();
        if (ethOut < minimumETHOut) revert SlippageExceeded();
        t.reserveETH -= gross;
        t.curveInventory += tokenAmount;
        t.price = _price(CURVE_SUPPLY - t.curveInventory);
        t.volume += gross;
        totalVolume += gross;
        _recordTrader(msg.sender);
        // Known, constructor-deployed ERC20 has no callbacks. Settle its balances before rewards.
        if (!LaunchToken(token).transferFrom(msg.sender, address(this), tokenAmount)) revert TokenTransferFailed();
        uint256 platformShare = _distributeFees(token, fee);
        emit Trade(token, msg.sender, false, gross, tokenAmount, fee, t.price);
        _sendETH(platformWallet, platformShare);
        _sendETH(msg.sender, ethOut);
    }

    /// @notice Quote net ETH from the reserve-function difference after the trade fee.
    function quoteSell(address token, uint256 tokenAmount) external view returns (uint256 ethOut) {
        (ethOut,,) = quoteSellDetail(token, tokenAmount);
    }

    /// @notice Quote net ETH, total fee and marginal price immediately after the main sale.
    /// @dev Reverts rather than silently underpaying if the gross amount is not backed.
    function quoteSellDetail(address token, uint256 tokenAmount)
        public view returns (uint256 ethOut, uint256 fee, uint256 newPrice)
    {
        TokenInfo storage t = _token(token);
        uint256 sold = CURVE_SUPPLY - t.curveInventory;
        if (tokenAmount > sold) revert InsufficientInventory();
        uint256 next = sold - tokenAmount;
        uint256 gross = _reserve(sold) - _reserve(next);
        if (gross > t.reserveETH) revert InsufficientReserve();
        fee = Math.mulDiv(gross, t.tradeFeeBps, BPS);
        return (gross - fee, fee, _price(next));
    }

    /// @notice Exact deterministic backing required at the current curve position.
    function reserveRequired(address token) external view returns (uint256) {
        return _reserve(CURVE_SUPPLY - _token(token).curveInventory);
    }

    /// @notice Collect only this token's creator share, including while paused.
    function claimCreatorFees(address token) external nonReentrant {
        if (msg.sender != _token(token).creator) revert NotCreator();
        uint256 amount = creatorFees[token];
        if (amount == 0) revert NothingToReceive();
        creatorFees[token] = 0;
        emit CreatorFeesClaimed(token, msg.sender, amount);
        _sendETH(msg.sender, amount);
    }

    /// @notice Collect the caller's dividend entitlement, including while paused.
    function claimHolderRewards(address token) external nonReentrant {
        _token(token);
        uint256 owed = LaunchToken(token).consumeRewards(msg.sender);
        if (owed == 0) revert NothingToReceive();
        holderPool[token] -= owed;
        emit HolderRewardsClaimed(token, msg.sender, owed);
        _sendETH(msg.sender, owed);
    }

    /// @notice Unwithdrawn holder ETH entitlement; launchpad-held tokens are excluded.
    function pendingHolderRewards(address token, address user) external view returns (uint256) {
        _token(token);
        return LaunchToken(token).pendingRewards(user);
    }

    /// @notice Create an active fundraise; exactly the creation fee must be supplied.
    function createFundraise(
        string memory name, string memory symbol, string memory logoURI,
        uint256 supply, uint256 targetETH, uint256 tradeFeeBps
    ) external payable nonReentrant whenNotPaused {
        _createFundraise(name, symbol, logoURI, supply, targetETH, tradeFeeBps, 0);
    }

    /// @notice Create a fundraise with instant release or 24/48 discrete hourly vesting steps.
    /// @dev Exactly the creation fee must be supplied; vesting starts when the target fills.
    function createFundraiseVested(
        string memory name, string memory symbol, string memory logoURI,
        uint256 supply, uint256 targetETH, uint256 tradeFeeBps, uint256 vestingHours
    ) external payable nonReentrant whenNotPaused {
        _createFundraise(name, symbol, logoURI, supply, targetETH, tradeFeeBps, vestingHours);
    }

    /// @dev Shared creation path; reentrancy and pause guards are applied by both entry points.
    function _createFundraise(
        string memory name, string memory symbol, string memory logoURI,
        uint256 supply, uint256 targetETH, uint256 tradeFeeBps, uint256 vestingHours
    ) private {
        if (vestingHours != 0 && vestingHours != 24 && vestingHours != 48) revert InvalidVesting();
        _validate(name, symbol, logoURI, supply, tradeFeeBps);
        if (targetETH < 0.01 ether || targetETH > MAX_TARGET || targetETH > _reserve(CURVE_SUPPLY)) {
            revert InvalidTarget();
        }
        if (_buyPosition(0, targetETH) > CURVE_SUPPLY) revert InvalidTarget();
        uint256 fee = fundraiseCreationFee;
        if (msg.value != fee) revert InvalidPayment();
        uint256 id = fundraiseList.length;
        Fundraise storage f = fundraiseList.push();
        f.creator = msg.sender;
        f.name = name;
        f.symbol = symbol;
        f.logoURI = logoURI;
        f.supply = supply;
        f.targetETH = targetETH;
        f.price = P0;
        f.tradeFeeBps = tradeFeeBps;
        f.deadline = block.timestamp + FUNDRAISE_DURATION;
        f.vestingHours = vestingHours;
        emit FundraiseCreated(id, msg.sender, targetETH);
        _sendETH(platformWallet, fee);
    }

    /// @notice Contribute without trade fees; reaching the target automatically launches.
    /// @dev The dust floor applies to msg.value, not the target-capped accepted amount.
    function contribute(uint256 id) external payable nonReentrant whenNotPaused {
        Fundraise storage f = _fundraise(id);
        if (f.status != 0) revert InvalidStatus();
        if (block.timestamp > f.deadline) revert FundraiseExpired();
        if (msg.value < MIN_TRADE) revert TradeTooSmall();
        uint256 amount = Math.min(msg.value, f.targetETH - f.raised);
        uint256 next = _buyPosition(f.sold, amount);
        uint256 allocation = next - f.sold;
        f.totalAllocated += allocation;
        f.sold = next;
        f.price = _price(next);
        f.raised += amount;
        ContributionInfo storage c = f.contributions[msg.sender];
        c.ethContributed += amount;
        c.tokensAllocated += allocation;
        emit Contribution(id, msg.sender, amount);
        if (f.raised == f.targetETH) _completeFundraise(id, f);
        _sendETH(msg.sender, msg.value - amount);
    }

    /// @notice Claim vested tokens from a completed fundraise, including while paused.
    function claim(uint256 id) external nonReentrant {
        Fundraise storage f = _fundraise(id);
        if (f.status != 1) revert InvalidStatus();
        ContributionInfo storage c = f.contributions[msg.sender];
        if (c.claimed) revert AlreadyProcessed();
        uint256 amount = _vestedAllocation(f, c.tokensAllocated) - c.claimedAmount;
        if (c.tokensAllocated == 0 || amount == 0) revert NothingToReceive();
        c.claimedAmount += amount;
        c.claimed = c.claimedAmount == c.tokensAllocated;
        emit Claimed(id, msg.sender, amount);
        if (!LaunchToken(f.token).transfer(msg.sender, amount)) revert TokenTransferFailed();
    }

    /// @dev Hourly floors release nothing before the first hour; the final step includes all dust.
    function _vestedAllocation(Fundraise storage f, uint256 allocation) private view returns (uint256) {
        uint256 duration = f.vestingHours;
        if (duration == 0) return allocation;
        uint256 elapsedHours = (block.timestamp - f.launchTime) / 1 hours;
        if (elapsedHours >= duration) return allocation;
        return allocation * elapsedHours / duration;
    }

    /// @notice Allow only an active fundraise's creator to cancel it, even while paused.
    function cancelFundraise(uint256 id) external nonReentrant {
        Fundraise storage f = _fundraise(id);
        if (msg.sender != f.creator) revert NotCreator();
        if (f.status != 0) revert InvalidStatus();
        f.status = 2;
        emit FundraiseCancelled(id);
    }

    /// @notice Unix time after which an unfilled fundraise accepts no contributions and can be refunded.
    function fundraiseDeadline(uint256 id) external view returns (uint256) {
        return _fundraise(id).deadline;
    }

    /// @notice Refund a contribution once, even while paused: after a cancel, or once an
    /// unfilled fundraise has passed its deadline (no creator action needed).
    function refund(uint256 id) external nonReentrant {
        Fundraise storage f = _fundraise(id);
        bool expired = f.status == 0 && block.timestamp > f.deadline;
        if (f.status != 2 && !expired) revert InvalidStatus();
        ContributionInfo storage c = f.contributions[msg.sender];
        if (c.refunded) revert AlreadyProcessed();
        uint256 amount = c.ethContributed;
        if (amount == 0) revert NothingToReceive();
        c.refunded = true;
        emit Refunded(id, msg.sender, amount);
        _sendETH(msg.sender, amount);
    }

    function _buy(address token, address buyer, uint256 amount, uint256 minimumTokensOut) private {
        TokenInfo storage t = _token(token);
        if (amount < MIN_TRADE) revert TradeTooSmall();
        uint256 fee = Math.mulDiv(amount, t.tradeFeeBps, BPS);
        uint256 net = amount - fee;
        uint256 sold = CURVE_SUPPLY - t.curveInventory;
        uint256 next = _buyPosition(sold, net);
        uint256 tokensOut = next - sold;
        if (tokensOut == 0) revert TradeTooSmall();
        if (tokensOut < minimumTokensOut) revert SlippageExceeded();
        t.reserveETH += net;
        t.curveInventory -= tokensOut;
        t.price = _price(next);
        t.volume += amount;
        totalVolume += amount;
        _recordTrader(buyer);
        if (!LaunchToken(token).transfer(buyer, tokensOut)) revert TokenTransferFailed();
        uint256 platformShare = _distributeFees(token, fee);
        emit Trade(token, buyer, true, amount, tokensOut, fee, t.price);
        _sendETH(platformWallet, platformShare);
    }

    /// @dev Rewards use balances after the main trade; burn changes only excluded inventory.
    /// FeesDistributed.burned is ETH assigned to the burn purchase, not a token quantity.
    function _distributeFees(address token, uint256 fee) private returns (uint256 platformShare) {
        uint256 creatorShare = Math.mulDiv(fee, 20, 100);
        uint256 holdersShare = Math.mulDiv(fee, 20, 100);
        uint256 burnShare = Math.mulDiv(fee, 20, 100);
        platformShare = fee - creatorShare - holdersShare - burnShare;
        creatorFees[token] += creatorShare;
        LaunchToken asset = LaunchToken(token);
        if (asset.circulating() < asset.MIN_REWARD_SUPPLY()) {
            platformShare += holdersShare;
            holdersShare = 0;
        } else if (holdersShare != 0) {
            holderPool[token] += holdersShare;
            asset.addRewards(holdersShare);
        }
        _burnBuy(token, burnShare);
        emit FeesDistributed(token, platformShare, creatorShare, holdersShare, burnShare);
    }

    function _burnBuy(address token, uint256 amount) private {
        if (amount == 0) return;
        TokenInfo storage t = tokens[token];
        uint256 sold = CURVE_SUPPLY - t.curveInventory;
        uint256 next;
        if (amount >= _reserve(CURVE_SUPPLY) - _reserve(sold)) next = CURVE_SUPPLY;
        else next = _buyPosition(sold, amount);
        uint256 burned = next - sold;
        t.reserveETH += amount;
        t.curveInventory -= burned;
        t.price = _price(next);
        if (burned != 0) LaunchToken(token).burn(burned);
        emit Burned(token, amount, burned);
    }

    function _completeFundraise(uint256 id, Fundraise storage f) private {
        address token = address(new LaunchToken(f.name, f.symbol, f.supply, address(this)));
        f.status = 1;
        f.launchTime = block.timestamp;
        f.token = token;
        tokens[token] = TokenInfo(
            f.creator, TOTAL_SUPPLY, f.price, CURVE_SUPPLY - f.sold,
            f.raised, f.raised, f.tradeFeeBps, true
        );
        tokenLogoURI[token] = f.logoURI;
        tokenList.push(token);
        totalVolume += f.raised;
        emit TokenCreated(token, f.creator, f.name, f.symbol);
        emit TokenLaunched(token, f.creator, f.price);
        emit FundraiseCompleted(id, token);
    }

    function _validate(
        string memory name, string memory symbol, string memory logoURI,
        uint256 supply, uint256 tradeFeeBps
    ) private pure {
        if (bytes(name).length == 0 || bytes(name).length > 64 ||
            bytes(symbol).length == 0 || bytes(symbol).length > 16 ||
            bytes(logoURI).length > 8000) revert InvalidMetadata();
        if (supply != TOTAL_SUPPLY) revert InvalidSupply();
        if (tradeFeeBps < 100 || tradeFeeBps > 300) revert InvalidFee();
    }

    /// @dev The only reserve definition used by buys, sells, fundraises and burns.
    function _reserve(uint256 sold) private pure returns (uint256) {
        return Math.mulDiv(A, _expWad(Math.mulDiv(K, sold, CURVE_SUPPLY)) - UNIT, UNIT);
    }

    function _price(uint256 sold) private pure returns (uint256) {
        return Math.mulDiv(P0, _expWad(Math.mulDiv(K, sold, CURVE_SUPPLY)), UNIT);
    }

    /// @dev Invert the reserve, round down, then verify against that very same reserve.
    /// Correction steps cover both wei rounding and one WAD-exponent quantization interval.
    /// At most eight conservative downward steps are allowed; there is no unbounded search.
    function _buyPosition(uint256 sold, uint256 net) private pure returns (uint256 next) {
        uint256 base = _reserve(sold);
        uint256 maximum = _reserve(CURVE_SUPPLY);
        if (net > maximum - base) revert InsufficientInventory();
        if (net == 0) return sold;
        uint256 target = base + net;
        if (target == maximum) return CURVE_SUPPLY;
        next = Math.mulDiv(CURVE_SUPPLY, _lnWad(UNIT + Math.mulDiv(target, UNIT, A)), K);
        if (next > CURVE_SUPPLY) revert InsufficientInventory();
        // Integer inversion may fall just behind the original position for a dust-sized budget.
        if (next < sold) next = sold;
        for (uint256 i; i < 8; ++i) {
            uint256 required = _reserve(next);
            if (required < base) revert CurveMathError();
            if (required - base <= net) return next;
            uint256 step = Math.mulDiv(required - target, UNIT, P0, Math.Rounding.Ceil)
                + CURVE_SUPPLY / K + 1;
            next = step >= next - sold ? sold : next - step;
        }
        revert CurveMathError();
    }

    /// @dev Original MIT, restricted-domain expWad: x in [0, ln(10)].
    /// Compute exp(x/4) with 36-decimal Taylor terms (40 terms), then square twice.
    /// Products are <=100e72, below uint256.max. Endpoint is explicitly normalized to 10 WAD.
    function _expWad(uint256 x) private pure returns (uint256) {
        if (x > K) revert CurveMathError();
        if (x == K) return 10 * UNIT;
        uint256 y = x * UNIT / 4;
        uint256 term = HIGH;
        uint256 sum = HIGH;
        for (uint256 i = 1; i <= 40; ++i) {
            term = term * y / HIGH / i;
            sum += term;
            if (term == 0) break;
        }
        sum = sum * sum / HIGH;
        sum = sum * sum / HIGH;
        return sum / UNIT;
    }

    /// @dev Original MIT, restricted-domain lnWad: x in [1, 10] WAD.
    /// Range-reduce to [1,2), then ln(z)=2*(u+u^3/3+...), u=(z-1)/(z+1).
    /// Sixty terms at 36 decimals; u<1/3. Discarded terms and divisions round downward.
    function _lnWad(uint256 x) private pure returns (uint256) {
        if (x < UNIT || x > 10 * UNIT) revert CurveMathError();
        uint256 z = x * UNIT;
        uint256 shifts;
        while (z >= 2 * HIGH) {
            z /= 2;
            ++shifts;
        }
        uint256 u = (z - HIGH) * HIGH / (z + HIGH);
        uint256 squared = u * u / HIGH;
        uint256 term = u;
        uint256 sum;
        for (uint256 i; i < 60; ++i) {
            sum += term / (2 * i + 1);
            term = term * squared / HIGH;
            if (term == 0) break;
        }
        return (2 * sum + shifts * LN2_HIGH) / UNIT;
    }

    function _token(address token) private view returns (TokenInfo storage t) {
        t = tokens[token];
        if (!t.launched) revert UnknownToken();
    }

    function _fundraise(uint256 id) private view returns (Fundraise storage f) {
        if (id >= fundraiseList.length) revert InvalidFundraise();
        f = fundraiseList[id];
    }

    function _recordTrader(address trader) private {
        if (!isTrader[trader]) {
            isTrader[trader] = true;
            traderList.push(trader);
        }
    }

    function _sendETH(address recipient, uint256 amount) private {
        if (amount == 0) return;
        (bool success,) = payable(recipient).call{value: amount}("");
        if (!success) revert ETHTransferFailed();
    }
}
