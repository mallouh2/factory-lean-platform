import { useRef, useState } from "react";
import { localName } from "@/components/ui";
import { localDateTimeToUtc } from "@/utils/manufacturing.mjs";
import type { FeatureProps } from "./types";

type Item = { key: number; productId: string; quantity: string; unit: string; query: string; open: boolean; active: number };
type ItemError = { product?: string; quantity?: string; unit?: string };
const blank = (key: number): Item => ({ key, productId: "", quantity: "", unit: "", query: "", open: false, active: -1 });

export default function CreateProductionOrder({ snapshot, t, lang, command, onCreated, onCancel }: FeatureProps & {
  onCreated: (id: string) => void; onCancel: () => void;
}) {
  const products = snapshot.tables.products || [];
  const [name, setName] = useState("");
  const [items, setItems] = useState<Item[]>([blank(0)]);
  const [priority, setPriority] = useState("normal");
  const [requiredBy, setRequiredBy] = useState("");
  const [notes, setNotes] = useState("");
  const [errors, setErrors] = useState<{ name?: string; items?: string; rows?: Record<number, ItemError>; requiredBy?: string; submit?: string }>({});
  const [busy, setBusy] = useState(false);
  const nextKey = useRef(1);
  const nameRef = useRef<HTMLInputElement>(null);
  const addRef = useRef<HTMLButtonElement>(null);
  const requester = String(snapshot.membership?.display_name || snapshot.user.email || "");
  const role = snapshot.tables.roles?.find((candidate) => String(candidate.id) === String(snapshot.membership?.role_id));
  const ownTitle = lang === "ar" ? snapshot.membership?.job_title_ar || snapshot.membership?.job_title : snapshot.membership?.job_title;
  const title = String(ownTitle || (role ? localName(role, lang) : ""));

  function updateItem(key: number, patch: Partial<Item>, clearError = true) {
    setItems((current) => current.map((item) => item.key === key ? { ...item, ...patch } : item));
    if (clearError) setErrors((current) => ({ ...current, items: undefined, rows: { ...current.rows, [key]: {} } }));
  }

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    const rows: Record<number, ItemError> = {};
    const selected = new Set<string>();
    for (const item of items) {
      const row: ItemError = {};
      if (!item.productId || !products.some((product) => String(product.id) === item.productId))
        row.product = "orderProductRequired";
      else if (selected.has(item.productId)) row.product = "orderDuplicateProduct";
      else selected.add(item.productId);
      if (!item.quantity.trim() || !Number.isFinite(Number(item.quantity)) || Number(item.quantity) <= 0)
        row.quantity = "orderQuantityPositive";
      if (!["meter", "piece"].includes(item.unit)) row.unit = "orderUnitRequired";
      if (Object.keys(row).length) rows[item.key] = row;
    }
    const nextErrors = {
      name: name.trim() ? undefined : "orderNameRequired",
      items: items.length ? undefined : "orderItemsRequired",
      rows,
    };
    setErrors(nextErrors);
    if (nextErrors.name) { nameRef.current?.focus(); return; }
    if (nextErrors.items) { addRef.current?.focus(); return; }
    const firstError = items.find((item) => rows[item.key]);
    if (firstError) {
      const field = rows[firstError.key].product ? "product" : rows[firstError.key].quantity ? "quantity" : "unit";
      document.getElementById(`request-${field}-${firstError.key}`)?.focus();
      return;
    }
    let requiredByUtc: string | null = null;
    try {
      if (requiredBy) requiredByUtc = localDateTimeToUtc(requiredBy, String(snapshot.factory?.timezone || "UTC"));
    } catch {
      setErrors((current) => ({ ...current, requiredBy: "orderRequiredByInvalid" }));
      document.getElementById("request-required-by")?.focus();
      return;
    }
    setBusy(true);
    try {
      const id = await command("create_production_request", {
        factory: snapshot.factory?.id,
        request_name: name.trim(),
        request_priority: priority,
        request_required_by: requiredByUtc,
        request_notes: notes.trim(),
        request_items: items.map((item) => ({ product_id: item.productId, quantity: Number(item.quantity), unit: item.unit })),
      });
      onCreated(String(id));
    } catch {
      setErrors((current) => ({ ...current, submit: "error" }));
    } finally {
      setBusy(false);
    }
  }

  return <form className="orders-v2-create-form" onSubmit={submit} noValidate>
    <div className="orders-v2-create-field">
      <label htmlFor="request-name">{t("productionRequestName")} <span aria-hidden="true">*</span></label>
      <input id="request-name" ref={nameRef} name="request_name" value={name} required maxLength={200}
        onChange={(event) => { setName(event.target.value); setErrors((current) => ({ ...current, name: undefined })); }}
        aria-invalid={Boolean(errors.name)} aria-describedby={errors.name ? "request-name-error" : undefined} />
      {errors.name && <p id="request-name-error" className="orders-v2-field-error" role="alert">{t(errors.name)}</p>}
    </div>

    <fieldset className="orders-v2-products">
      <legend>{t("requestProducts")} <span aria-hidden="true">*</span></legend>
      {items.map((item, index) => {
        const selectedProduct = products.find((product) => String(product.id) === item.productId);
        const available = products.filter((product) => !product.archived || String(product.id) === item.productId);
        const matches = available.filter((product) =>
          `${localName(product, lang)} ${product.code || ""}`.toLocaleLowerCase(lang)
            .includes(item.query.toLocaleLowerCase(lang)));
        const rowError = errors.rows?.[item.key] || {};
        const chooseProduct = (product: (typeof products)[number]) =>
          updateItem(item.key, { productId: String(product.id), query: "", open: false, active: -1 });
        return <div className="orders-v2-product-row" key={item.key}>
          <div className="orders-v2-create-field orders-v2-product-pick">
            <label htmlFor={`request-product-${item.key}`}>{t("product")} <span aria-hidden="true">*</span></label>
            <div className="orders-v2-product-combobox">
              <input id={`request-product-${item.key}`} role="combobox" type="text" required autoComplete="off"
                value={item.query || (selectedProduct ? localName(selectedProduct, lang) : "")}
                placeholder={t("orderSelectProduct")}
                aria-autocomplete="list" aria-expanded={item.open}
                aria-controls={`request-product-options-${item.key}`}
                aria-activedescendant={item.open && item.active >= 0 && matches[item.active]
                  ? `request-product-option-${item.key}-${matches[item.active].id}` : undefined}
                aria-invalid={Boolean(rowError.product)} aria-describedby={rowError.product ? `request-product-error-${item.key}` : undefined}
                onFocus={() => updateItem(item.key, { query: "", open: true, active: -1 }, false)}
                onBlur={() => updateItem(item.key, { open: false, active: -1 }, false)}
                onChange={(event) => updateItem(item.key, { productId: "", query: event.target.value, open: true, active: -1 })}
                onKeyDown={(event) => {
                  if (event.key === "ArrowDown" || event.key === "ArrowUp") {
                    event.preventDefault();
                    if (!item.open) { updateItem(item.key, { query: "", open: true, active: event.key === "ArrowDown" ? 0 : available.length - 1 }, false); return; }
                    if (matches.length) updateItem(item.key, { active: event.key === "ArrowDown"
                      ? (item.active + 1) % matches.length : (item.active + matches.length - 1) % matches.length }, false);
                  } else if (event.key === "Enter" && item.open && item.active >= 0 && matches[item.active]) {
                    event.preventDefault();
                    chooseProduct(matches[item.active]);
                  } else if (event.key === "Escape" && item.open) {
                    event.preventDefault();
                    updateItem(item.key, { open: false, active: -1 }, false);
                  }
                }} />
              <span className="orders-v2-product-caret" aria-hidden="true">⌄</span>
              {item.open && <ul id={`request-product-options-${item.key}`} className="orders-v2-product-options" role="listbox">
                {matches.length ? matches.map((product, matchIndex) =>
                  <li key={String(product.id)} id={`request-product-option-${item.key}-${product.id}`}
                    role="option" aria-selected={String(product.id) === item.productId}
                    className={matchIndex === item.active ? "is-active" : ""}
                    onPointerDown={(event) => event.preventDefault()} onClick={() => chooseProduct(product)}>
                    {localName(product, lang)}{product.code ? <small>{String(product.code)}</small> : null}
                  </li>) : <li className="orders-v2-product-empty" role="presentation">{t("noResults")}</li>}
              </ul>}
            </div>
            {rowError.product && <p id={`request-product-error-${item.key}`} className="orders-v2-field-error" role="alert">{t(rowError.product)}</p>}
          </div>
          <div className="orders-v2-create-field">
            <label htmlFor={`request-quantity-${item.key}`}>{t("orderRequiredQuantity")}</label>
            <input id={`request-quantity-${item.key}`} type="number" inputMode="decimal" step="any" required
              value={item.quantity} onChange={(event) => updateItem(item.key, { quantity: event.target.value })}
              aria-invalid={Boolean(rowError.quantity)} aria-describedby={rowError.quantity ? `request-quantity-error-${item.key}` : undefined} />
            {rowError.quantity && <p id={`request-quantity-error-${item.key}`} className="orders-v2-field-error" role="alert">{t(rowError.quantity)}</p>}
          </div>
          <div className="orders-v2-create-field">
            <label htmlFor={`request-unit-${item.key}`}>{t("unit")}</label>
            <select id={`request-unit-${item.key}`} value={item.unit} required
              onChange={(event) => updateItem(item.key, { unit: event.target.value })}
              aria-invalid={Boolean(rowError.unit)} aria-describedby={rowError.unit ? `request-unit-error-${item.key}` : undefined}>
              <option value="">{t("notSpecified")}</option>
              <option value="meter">{t("meter")}</option>
              <option value="piece">{t("piece")}</option>
            </select>
            {rowError.unit && <p id={`request-unit-error-${item.key}`} className="orders-v2-field-error" role="alert">{t(rowError.unit)}</p>}
          </div>
          <button className="orders-v2-remove-item" type="button" aria-label={`${t("removeProduct")} ${index + 1}`}
            onClick={() => { setItems((current) => current.filter((entry) => entry.key !== item.key)); setErrors({}); }}>
            {t("removeProduct")}
          </button>
        </div>;
      })}
      {errors.items && <p className="orders-v2-field-error" role="alert">{t(errors.items)}</p>}
      <button ref={addRef} className="orders-v2-add-item" type="button" onClick={() => setItems((current) => [...current, blank(nextKey.current++)])}>
        + {t("addProduct")}
      </button>
    </fieldset>

    <div className="orders-v2-create-extras">
      <div className="orders-v2-create-field">
        <label htmlFor="request-requester">{t("requestedBy")}</label>
        <input id="request-requester" value={title ? `${requester} · ${title}` : requester} readOnly aria-readonly="true" />
      </div>
      <div className="orders-v2-create-field">
        <label htmlFor="request-priority">{t("priority")}</label>
        <select id="request-priority" value={priority} onChange={(event) => setPriority(event.target.value)}>
          {(["low", "normal", "high", "urgent"] as const).map((value) =>
            <option key={value} value={value}>{t(`priority_${value}`)}</option>)}
        </select>
      </div>
      <div className="orders-v2-create-field">
        <label htmlFor="request-required-by">{t("requiredBy")}</label>
        <input id="request-required-by" type="datetime-local" value={requiredBy}
          onChange={(event) => { setRequiredBy(event.target.value); setErrors((current) => ({ ...current, requiredBy: undefined })); }}
          aria-invalid={Boolean(errors.requiredBy)} aria-describedby={errors.requiredBy ? "request-required-by-error" : undefined} />
        {errors.requiredBy && <p id="request-required-by-error" className="orders-v2-field-error" role="alert">{t(errors.requiredBy)}</p>}
      </div>
      <div className="orders-v2-create-field orders-v2-notes">
        <label htmlFor="request-notes">{t("notes")}</label>
        <textarea id="request-notes" rows={2} maxLength={2000} value={notes}
          onChange={(event) => setNotes(event.target.value)} />
      </div>
    </div>
    {errors.submit && <p className="orders-v2-field-error" role="alert">{t(errors.submit)}</p>}
    <div className="orders-v2-create-actions">
      <button type="button" onClick={onCancel}>{t("cancel")}</button>
      <button className="primary" type="submit" disabled={busy}>{t("createProductionRequest")}</button>
    </div>
  </form>;
}
