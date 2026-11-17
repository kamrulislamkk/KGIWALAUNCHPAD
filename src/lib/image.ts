/**
 * Client-side logo processing: crop to a square, shrink, and encode as a small data URI
 * so it can be stored onchain as the token's logoURI.
 */

export const MAX_LOGO_BYTES = 4096
const MAX_INPUT_BYTES = 8 * 1024 * 1024

function loadImage(file: File): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      URL.revokeObjectURL(url)
      resolve(img)
    }
    img.onerror = () => {
      URL.revokeObjectURL(url)
      reject(new Error('That file could not be read as an image.'))
    }
    img.src = url
  })
}

function render(img: HTMLImageElement, size: number, mime: string, quality: number): string {
  const canvas = document.createElement('canvas')
  canvas.width = size
  canvas.height = size
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('Image processing is not available in this browser.')
  const side = Math.min(img.naturalWidth, img.naturalHeight)
  const sx = (img.naturalWidth - side) / 2
  const sy = (img.naturalHeight - side) / 2
  ctx.drawImage(img, sx, sy, side, side, 0, 0, size, size)
  return canvas.toDataURL(mime, quality)
}

/** Returns a data URI no larger than MAX_LOGO_BYTES, or throws a readable error. */
export async function fileToLogoDataUri(file: File): Promise<string> {
  if (!file.type.startsWith('image/')) throw new Error('Choose an image file (PNG, JPG, WebP).')
  if (file.size > MAX_INPUT_BYTES) throw new Error('Image is too large. Choose one under 8 MB.')
  const img = await loadImage(file)

  const sizes = [96, 80, 64, 48]
  const qualities = [0.8, 0.6, 0.45, 0.3]
  for (const size of sizes) {
    for (const quality of qualities) {
      const uri = render(img, size, 'image/webp', quality)
      if (uri.startsWith('data:image/webp') && uri.length <= MAX_LOGO_BYTES) return uri
    }
  }
  // Browsers without WebP encoding fall back to PNG/JPEG; try JPEG as a last resort.
  for (const size of sizes) {
    const uri = render(img, size, 'image/jpeg', 0.5)
    if (uri.length <= MAX_LOGO_BYTES) return uri
  }
  throw new Error('Could not shrink that image enough. Try a simpler logo.')
}
