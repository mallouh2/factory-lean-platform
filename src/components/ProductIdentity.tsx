import type { CSSProperties, ReactNode } from 'react';
import { productColor } from '@/utils/product-colors.mjs';

/** Product identity remains stable even when its catalog row is not loaded. */
export default function ProductIdentity({ productId, productItemId, children }: {
  productId: unknown; productItemId?: unknown; children: ReactNode;
}) {
  const tone = productColor(productId, productItemId);
  return <span className="product-identity" data-product-id={String(productId || '')}
    style={{ '--product-surface': tone.surface, '--product-ink': tone.ink,
      '--product-edge': tone.edge } as CSSProperties}>
    <span className="product-identity-marker" aria-hidden="true" />{children}
  </span>;
}
