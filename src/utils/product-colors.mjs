/** Product identity only: operational status colors remain separate. */
// Generate a coherent HSL family, then serialize to hex identically on server/client.
function hslHex(hue, saturation, lightness) {
  const s = saturation / 100, l = lightness / 100;
  const a = s * Math.min(l, 1 - l);
  const channel = (n) => {
    const k = (n + hue / 30) % 12;
    return Math.round(255 * (l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))))
      .toString(16).padStart(2, "0");
  };
  return `#${channel(0)}${channel(8)}${channel(4)}`;
}

function stableId(value) {
  if (typeof value !== "string" || !value.trim()) return null;
  const id = value.trim();
  // Database IDs are UUIDs; retain opaque nonempty string IDs for legacy records.
  return /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(id) ? id.toLowerCase() : id;
}

/** FNV-1a with avalanche mixing and direct, controlled HSL derivation.
 * Missing Product IDs use the stable Product Item ID (History's order_id),
 * then a fixed unknown sentinel. Never use names, codes, catalog or session state.
 * @param {unknown} productId
 * @param {unknown} [productItemId]
 */
export function productColor(productId, productItemId = null) {
  const id = stableId(productId);
  const itemId = id ? null : stableId(productItemId);
  const key = id || (itemId ? `legacy-item:${itemId}` : "unknown-product");
  let hash = 2166136261;
  for (let index = 0; index < key.length; index++) {
    hash = Math.imul(hash ^ key.charCodeAt(index), 16777619) >>> 0;
  }
  // Mix identity independently of catalog order, names, locale and page.
  hash = Math.imul(hash ^ (hash >>> 16), 0x85ebca6b) >>> 0;
  hash = Math.imul(hash ^ (hash >>> 13), 0xc2b2ae35) >>> 0;
  hash = (hash ^ (hash >>> 16)) >>> 0;
  // Checked identity families: deep earth, red-violet plum, and rose-fuchsia.
  // Earth stays dark (not amber); plum stays redward of blocked violet;
  // rose stays short of alert red. No green, cyan or scheduled-blue family.
  const family = (hash >>> 26) % 3;
  const fraction = (hash & 0xffff) / 65536;
  const hue = [24, 290, 315][family] + fraction * [10, 12, 12][family];
  const saturation = [38, 45, 60][family] + (hash >>> 9) % 15;
  const shade = (hash >>> 25) & 1;
  const lightness = [22, 24, 48][family] + shade * [14, 14, 6][family] + (hash >>> 17) % 4;
  return Object.freeze({
    surface: hslHex(hue, saturation, 85 + shade * 5 + (hash >>> 21) % 2),
    ink: hslHex(hue, saturation, 22 + (hash >>> 24) % 4),
    edge: hslHex(hue, saturation, lightness),
  });
}
