import { useEffect, useState } from "react";
import type { FeatureProps } from "./types";
import type { Row } from "@/types";
import { localName, Badge, Field } from "@/components/ui";
import Configuration from "./Configuration";
import CenterCapabilities from "./CenterCapabilities";
export default function LineBuilder(
  props: FeatureProps & { onDirtyChange?: (dirty: boolean) => void },
) {
  const { snapshot: s, t, lang, command, can } = props;
  const [draft, setDraft] = useState<Row[] | null>(null),
    [version, setVersion] = useState(0),
    [busy, setBusy] = useState(false),
    [selected, setSelected] = useState(""),
    [panels, setPanels] = useState({ line: false, machine: false, areas: false });
  useEffect(() => {
    props.onDirtyChange?.(!!draft);
    const warn = (e: BeforeUnloadEvent) => {
      if (draft) {
        e.preventDefault();
        e.returnValue = "";
      }
    };
    window.addEventListener("beforeunload", warn);
    return () => {
      props.onDirtyChange?.(false);
      window.removeEventListener("beforeunload", warn);
    };
  }, [!!draft, props.onDirtyChange]);
  const centers =
    draft || (s.tables.work_centers || []).filter((c) => !c.archived);
  const lines = (s.tables.production_lines || []).filter((l) => !l.archived);
  const editable = can("lines", "edit") && can("centers", "edit");
  function change(next: Row[]) {
    if (!editable) return;
    if (!draft) {
      setVersion(Number(s.factory?.structure_version));
      // Record forms edit saved state; creating while drafting would bump the
      // structure version and invalidate the pending arrangement.
      setPanels({ line: false, machine: false, areas: false });
    }
    setDraft(next);
  }
  function openPanel(key: "line" | "machine" | "areas") {
    if (draft) {
      if (!confirm(t("discardChanges"))) return;
      setDraft(null);
    }
    setPanels((p) => ({ ...p, [key]: true }));
  }
  const guardSummary =
    (key: "line" | "machine" | "areas") =>
    (e: React.MouseEvent<HTMLElement>) => {
      if (draft) {
        e.preventDefault();
        openPanel(key);
      }
    };
  function move(id: string, line: string, index: number) {
    const item = centers.find((c) => c.id === id);
    if (!item) return;
    const siblings = centers
      .filter((c) => c.id !== id && (c.line_id || "") === line)
      .sort((a, b) => Number(a.position) - Number(b.position));
    siblings.splice(Math.max(0, index), 0, {
      ...item,
      line_id: line || null,
      dependency_mode: line
        ? item.dependency_mode === "independent"
          ? "non_blocking"
          : item.dependency_mode
        : "independent",
    });
    const updated: Row[] = siblings.map((c, i) => ({ ...c, position: i }));
    change([
      ...centers.filter((c) => !updated.some((x) => x.id === c.id)),
      ...updated,
    ]);
  }
  async function save() {
    setBusy(true);
    try {
      await command("save_line_layout", {
        factory: s.factory?.id,
        version,
        layout: centers.map((c) => ({
          id: c.id,
          line_id: c.line_id,
          position: c.position,
          dependency_mode: c.dependency_mode,
          buffer_minutes: Number(c.buffer_minutes),
          impact_scope: c.impact_scope,
        })),
      });
      setDraft(null);
    } catch {
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <section className="panel">
        <header className="section-head">
          <div>
            <h2>{t("lineBuilder")}</h2>
            <p>{t("builderHelp")}</p>
          </div>
          <div className="row-actions">
            <button
              disabled={!draft || busy}
              onClick={() => {
                if (confirm(t("discardChanges"))) setDraft(null);
              }}
            >
              {t("cancel")}
            </button>
            <button
              className="primary"
              disabled={!draft || busy}
              onClick={() => void save()}
            >
              {t("saveLayout")}
            </button>
          </div>
        </header>
        {draft && <p role="status">{t("unsavedLayout")}</p>}
        <div className="row-actions">
          {can("lines", "create") && (
            <button disabled={busy} onClick={() => openPanel("line")}>
              + {t("createLine")}
            </button>
          )}
          {can("centers", "create") && (
            <button
              className="primary"
              disabled={busy}
              onClick={() => openPanel("machine")}
            >
              + {t("addMachine")}
            </button>
          )}
        </div>
        <div className="builder-grid">
          {[{ id: "", name: t("availableMachines") }, ...lines].map((line) => {
            const group = centers
              .filter((c) => (c.line_id || "") === line.id)
              .sort((a, b) => Number(a.position) - Number(b.position));
            return (
              <section
                className="builder-line"
                data-drop-line={String(line.id)}
                data-drop-index={group.length}
                key={String(line.id)}
                onDragOver={(e) => {
                  if (editable) e.preventDefault();
                }}
                onDrop={(e) => {
                  e.preventDefault();
                  move(
                    e.dataTransfer.getData("text/plain"),
                    String(line.id),
                    group.length,
                  );
                }}
              >
                <h3>{localName(line, lang)}</h3>
                {!group.length && <p className="muted">{t("dropMachine")}</p>}
                {group.map((c, i) => (
                  <article
                    className="builder-machine"
                    data-drop-line={String(line.id)}
                    data-drop-index={i}
                    key={String(c.id)}
                    draggable={editable && !busy}
                    onDragStart={(e) =>
                      e.dataTransfer.setData("text/plain", String(c.id))
                    }
                    onDragOver={(e) => {
                      if (editable) e.preventDefault();
                    }}
                    onDrop={(e) => {
                      e.preventDefault();
                      e.stopPropagation();
                      move(
                        e.dataTransfer.getData("text/plain"),
                        String(line.id),
                        i,
                      );
                    }}
                  >
                    <button
                      type="button"
                      className="drag-handle"
                      disabled={!editable || busy}
                      aria-label={t("dragMachine") + " " + localName(c, lang)}
                      onPointerDown={(e) => {
                        e.preventDefault();
                        e.currentTarget.setPointerCapture(e.pointerId);
                      }}
                      onPointerUp={(e) => {
                        const target = document
                          .elementFromPoint(e.clientX, e.clientY)
                          ?.closest<HTMLElement>("[data-drop-line]");
                        if (target)
                          move(
                            String(c.id),
                            target.dataset.dropLine || "",
                            Number(target.dataset.dropIndex),
                          );
                        e.currentTarget.releasePointerCapture(e.pointerId);
                      }}
                    >
                      ⠿ <strong>⚙ {localName(c, lang)}</strong>
                    </button>
                    <small>{String(c.code)}</small>
                    <Badge status={String(c.status)} t={t} />
                    <div className="row-actions">
                      <button
                        disabled={!editable || i === 0}
                        aria-label={t("moveUp")}
                        onClick={() =>
                          move(String(c.id), String(line.id), i - 1)
                        }
                      >
                        ↑
                      </button>
                      <button
                        disabled={!editable || i === group.length - 1}
                        aria-label={t("moveDown")}
                        onClick={() =>
                          move(String(c.id), String(line.id), i + 1)
                        }
                      >
                        ↓
                      </button>
                      <button
                        onClick={() =>
                          setSelected(selected === c.id ? "" : String(c.id))
                        }
                      >
                        {t("configure")}
                      </button>
                    </div>
                    <Field label={t("moveTo")}>
                      <select
                        disabled={!editable}
                        value={String(c.line_id || "")}
                        onChange={(e) =>
                          move(String(c.id), e.target.value, centers.length)
                        }
                      >
                        <option value="">{t("independent")}</option>
                        {lines.map((l) => (
                          <option value={String(l.id)} key={String(l.id)}>
                            {localName(l, lang)}
                          </option>
                        ))}
                      </select>
                    </Field>
                    {selected === c.id && (
                      <>
                        <Field label={t("dependencyMode")}>
                          <select
                            disabled={!editable || !c.line_id}
                            value={String(c.dependency_mode)}
                            onChange={(e) =>
                              change(
                                centers.map((x) =>
                                  x.id === c.id
                                    ? {
                                        ...x,
                                        dependency_mode: e.target.value,
                                        impact_scope: [
                                          "non_blocking",
                                          "independent",
                                        ].includes(e.target.value)
                                          ? "none"
                                          : x.impact_scope === "none"
                                            ? "downstream"
                                            : x.impact_scope,
                                      }
                                    : x,
                                ),
                              )
                            }
                          >
                            {[
                              "blocking",
                              "non_blocking",
                              "independent",
                              "buffer",
                            ].map((m) => (
                              <option value={m} key={m}>
                                {t(m)}
                              </option>
                            ))}
                          </select>
                        </Field>
                        <Field label={t("impactScope")}>
                          <select
                            disabled={!editable || !c.line_id}
                            value={String(
                              ["non_blocking", "independent"].includes(
                                String(c.dependency_mode),
                              )
                                ? "none"
                                : c.impact_scope || "downstream",
                            )}
                            onChange={(e) =>
                              change(
                                centers.map((x) =>
                                  x.id === c.id
                                    ? {
                                        ...x,
                                        impact_scope: e.target.value,
                                        dependency_mode:
                                          e.target.value === "none"
                                            ? "non_blocking"
                                            : x.dependency_mode === "buffer"
                                              ? "buffer"
                                              : "blocking",
                                      }
                                    : x,
                                ),
                              )
                            }
                          >
                            {["whole_line", "downstream", "none"].map((m) => (
                              <option key={m} value={m}>
                                {t(m)}
                              </option>
                            ))}
                          </select>
                        </Field>
                        {c.dependency_mode === "buffer" && (
                          <Field label={t("bufferMinutes")}>
                            <input
                              type="number"
                              min={1}
                              max={10080}
                              value={Number(c.buffer_minutes)}
                              disabled={!editable}
                              onChange={(e) =>
                                change(
                                  centers.map((x) =>
                                    x.id === c.id
                                      ? {
                                          ...x,
                                          buffer_minutes: Number(
                                            e.target.value,
                                          ),
                                        }
                                      : x,
                                  ),
                                )
                              }
                            />
                          </Field>
                        )}
                        {!draft && (
                          <CenterCapabilities
                            {...props}
                            centerId={String(c.id)}
                          />
                        )}
                      </>
                    )}
                  </article>
                ))}
              </section>
            );
          })}
        </div>
      </section>
      <details
        className="panel"
        open={panels.line}
        onToggle={(e) =>
          setPanels((p) => ({ ...p, line: e.currentTarget.open }))
        }
      >
        <summary onClick={guardSummary("line")}>{t("createLine")}</summary>
        <Configuration {...props} view="lines" />
      </details>
      <details
        className="panel"
        open={panels.machine}
        onToggle={(e) =>
          setPanels((p) => ({ ...p, machine: e.currentTarget.open }))
        }
      >
        <summary onClick={guardSummary("machine")}>{t("addMachine")}</summary>
        <Configuration {...props} view="centers" />
      </details>
      <details
        className="panel"
        open={panels.areas}
        onToggle={(e) =>
          setPanels((p) => ({ ...p, areas: e.currentTarget.open }))
        }
      >
        <summary onClick={guardSummary("areas")}>{t("areasOptional")}</summary>
        <Configuration {...props} view="factory" />
      </details>
    </>
  );
}
