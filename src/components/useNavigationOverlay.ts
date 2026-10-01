import { useEffect, useRef } from 'react';

/** Overlay state belongs to the shell; it never selects or remounts a page. */
export function useNavigationOverlay(mobile: boolean, setMobile: (open: boolean) => void,
  setCollapsed: (collapsed: boolean) => void) {
  const sidebarRef = useRef<HTMLElement>(null);
  const menuRef = useRef<HTMLButtonElement>(null);
  const pointerInside = useRef(false);
  const keyboardMode = useRef(false);
  const collapseTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const wasMobile = useRef(false);
  function cancelCollapse() {
    if (collapseTimer.current) clearTimeout(collapseTimer.current);
    collapseTimer.current = null;
  }
  function collapseWhenOutside() {
    cancelCollapse();
    collapseTimer.current = setTimeout(() => {
      if (!pointerInside.current && (!keyboardMode.current || !sidebarRef.current?.contains(document.activeElement))) setCollapsed(true);
    }, 150);
  }
  useEffect(() => () => cancelCollapse(), []);
  useEffect(() => {
    const keyboard = (event: KeyboardEvent) => { if (event.key === 'Tab') keyboardMode.current = true; };
    const pointer = () => { keyboardMode.current = false; };
    document.addEventListener('keydown', keyboard);
    document.addEventListener('pointerdown', pointer);
    return () => { document.removeEventListener('keydown', keyboard); document.removeEventListener('pointerdown', pointer); };
  }, []);
  useEffect(() => {
    if (mobile) sidebarRef.current?.querySelector<HTMLButtonElement>('.sidebar-close')?.focus();
    else if (wasMobile.current) menuRef.current?.focus();
    wasMobile.current = mobile;
  }, [mobile]);
  return { sidebarRef, menuRef,
    onPointerEnter: (event: React.PointerEvent<HTMLElement>) => {
      if (event.pointerType === 'touch' || !window.matchMedia('(min-width: 901px) and (hover: hover)').matches) return;
      pointerInside.current = true; cancelCollapse(); setCollapsed(false);
    },
    onPointerLeave: () => { pointerInside.current = false; collapseWhenOutside(); },
    onFocusCapture: () => {
      cancelCollapse();
      if (window.matchMedia('(min-width: 901px)').matches) setCollapsed(false);
    },
    onBlurCapture: collapseWhenOutside,
    onKeyDown: (event: React.KeyboardEvent<HTMLElement>) => {
      if (event.key === 'Escape') {
        event.preventDefault(); event.stopPropagation(); cancelCollapse();
        setCollapsed(true); if (mobile) setMobile(false);
      }
      if (!mobile || event.key !== 'Tab') return;
      const controls = sidebarRef.current?.querySelectorAll<HTMLElement>(
        'a[href],button:not([disabled]),select:not([disabled]),summary');
      const visible = Array.from(controls || []).filter(element => element.getClientRects().length);
      const first = visible[0], last = visible.at(-1);
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
    },
  };
}
