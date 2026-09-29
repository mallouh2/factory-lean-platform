import { useEffect, useRef, useState } from "react";
import type { FeatureProps } from "./types";
import type { Row } from "@/types";
import { Field, localName } from "@/components/ui";
import MachineIcon from "@/components/MachineIcon";
import FactoryRoute from "@/components/FactoryRoute";
import { categoryIconKey } from "@/utils/floor-visual.mjs";
import Configuration from "./Configuration";

type Screen =
  | { kind: "overview" }
  | { kind: "line" | "machine"; id: string }
  | { kind: "createLine" | "createMachine" | "areas" | "categories" };

export default function LineBuilder(props: FeatureProps & {
  initialMachineId?: string | null;
  onBackToFloor?: () => void;
  onDirtyChange?: (dirty: boolean) => void;
}) {
  const { snapshot: s, t, lang, command, can } = props;
  const [screen, setScreen] = useState<Screen>(
    props.initialMachineId ? { kind: "machine", id: props.initialMachineId } : { kind: "overview" },
  );
  const [draft, setDraft] = useState<Row[] | null>(null);
  const [version, setVersion] = useState(0);
  const [busy, setBusy] = useState(false);
  const initialHeadingRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    if (props.initialMachineId) initialHeadingRef.current?.focus();
  }, [props.initialMachineId]);
  const savedCenters = (s.tables.work_centers || []).filter((c) => !c.archived);
  const centers = draft || savedCenters;
  const lines = (s.tables.production_lines || []).filter((l) => !l.archived);
  const editable = can("lines", "edit") && can("centers", "edit");

  useEffect(() => {
    props.onDirtyChange?.(!!draft);
    const warn = (event: BeforeUnloadEvent) => {
      if (draft) { event.preventDefault(); event.returnValue = ""; }
    };
    window.addEventListener("beforeunload", warn);
    return () => { props.onDirtyChange?.(false); window.removeEventListener("beforeunload", warn); };
  }, [!!draft, props.onDirtyChange]);

  function go(next: Screen) {
    if (draft && !confirm(t("discardChanges"))) return;
    setDraft(null);
    if (next.kind === "overview" && props.initialMachineId && props.onBackToFloor) {
      props.onBackToFloor();
    } else setScreen(next);
  }
  function change(next: Row[]) {
    if (!editable) return;
    if (!draft) setVersion(Number(s.factory?.structure_version));
    setDraft(next);
  }
  function move(id: string, lineId: string, index: number) {
    const item = centers.find((c) => String(c.id) === id);
    if (!item) return;
    const siblings = centers
      .filter((c) => String(c.id) !== id && String(c.line_id || "") === lineId)
      .sort((a, b) => Number(a.position) - Number(b.position));
    siblings.splice(Math.max(0, index), 0, {
      ...item,
      line_id: lineId || null,
      dependency_mode: lineId
        ? item.dependency_mode === "independent" ? "non_blocking" : item.dependency_mode
        : "independent",
    });
    const updated: Row[] = siblings.map((c, position) => ({ ...c, position }));
    change([...centers.filter((c) => !updated.some((x) => x.id === c.id)), ...updated]);
  }
  async function saveLayout() {
    if (!draft) return;
    setBusy(true);
    try {
      await command("save_line_layout", {
        factory: s.factory?.id,
        version,
        layout: centers.map((c) => ({
          id: c.id, line_id: c.line_id, position: c.position,
          dependency_mode: c.dependency_mode,
          buffer_minutes: Number(c.buffer_minutes), impact_scope: c.impact_scope,
        })),
      });
      setDraft(null);
      if (props.initialMachineId && props.onBackToFloor) props.onBackToFloor();
      else setScreen({ kind: "overview" });
    } catch {
      // The shared command reports a layout conflict and refreshes the snapshot.
    } finally { setBusy(false); }
  }
  const ordered = (lineId: string) => centers
    .filter((c) => String(c.line_id || "") === lineId)
    .sort((a, b) => Number(a.position) - Number(b.position) || String(a.id).localeCompare(String(b.id)));
  const machineCard = (machine: Row) => {
    const category = (s.tables.work_center_categories || []).find((x) => x.id === machine.category_id);
    return <button className="management-machine" onClick={() => go({ kind: "machine", id: String(machine.id) })}>
      <MachineIcon center={machine} running={false}
        categoryIconKey={categoryIconKey(machine, s.tables.work_center_categories) || undefined} />
      <strong dir="auto">{localName(machine, lang)}</strong>
      <span dir="auto">{category ? localName(category, lang) : t(String(machine.type || "machine"))}</span>
    </button>;
  };
  const lineCard = (line: Row | null) => {
    const lineId = String(line?.id || "");
    const machines = ordered(lineId);
    if (!line && !machines.length) return null;
    return <section className="management-line" key={lineId || "unassigned"}>
      <div className="management-line-body">
        {line ? <button className="management-line-anchor" onClick={() => go({ kind: "line", id: lineId })}>
          <span className="management-line-symbol" aria-hidden="true">▤</span>
          <strong dir="auto">{localName(line, lang)}</strong>
          <small><bdi dir="ltr">{String(line.code || "")}</bdi> · {machines.length} {t("machines")}</small>
        </button> : <div className="management-line-anchor management-unassigned">
          <span className="management-line-symbol" aria-hidden="true">▤</span>
          <strong>{t("availableMachines")}</strong>
          <small>{machines.length} {t("machines")}</small>
        </div>}
        {!!machines.length && <span className="management-line-arrow" aria-hidden="true">→</span>}
        <div className="management-route">
          {machines.length ? <FactoryRoute machines={machines} renderMachine={machineCard}
            connectorActive={() => false} continuationLabel={t("routeContinues")} />
            : <p className="management-empty">{t("noMachinesOnLine")}</p>}
        </div>
      </div>
    </section>;
  };
  const selectedLine = screen.kind === "line" ? lines.find((l) => String(l.id) === screen.id) : undefined;
  const selectedMachine = screen.kind === "machine" ? centers.find((c) => String(c.id) === screen.id) : undefined;
  const savedMachine = screen.kind === "machine" ? savedCenters.find((c) => String(c.id) === screen.id) : undefined;
  const machineSiblings = selectedMachine ? ordered(String(selectedMachine.line_id || "")) : [];
  const machineIndex = selectedMachine ? machineSiblings.findIndex((c) => c.id === selectedMachine.id) : -1;

  return <section className="management ff2">
    {screen.kind === "overview" ? <>
      <header className="management-head">
        <div><h2>{t("manageLinesMachines")}</h2><p>{t("managementHelp")}</p></div>
        <div className="management-actions">
          {can("lines", "create") && <button onClick={() => go({ kind: "createLine" })}>+ {t("addLine")}</button>}
          {can("centers", "create") && <button className="primary" onClick={() => go({ kind: "createMachine" })}>+ {t("addMachineShort")}</button>}
        </div>
      </header>
      {!lines.length && !savedCenters.length && <p className="management-empty">{t("noLinesYet")}</p>}
      <div className="management-line-list">{lines.map(lineCard)}{lineCard(null)}</div>
      <div className="management-secondary">
        {can("factory", "view") && <button onClick={() => go({ kind: "areas" })}>{t("areasOptional")}</button>}
        {can("centers", "view") && <button onClick={() => go({ kind: "categories" })}>{t("manageCategories")}</button>}
      </div>
    </> : <>
      <header className="management-subhead">
        <button className="line-management-back" onClick={() => go({ kind: "overview" })}>← {t(props.initialMachineId ? "backToFactoryFloor" : "backToLinesMachines")}</button>
        <div><p>{t("manageLinesMachines")}</p><h2 ref={initialHeadingRef} tabIndex={-1}>{
          screen.kind === "line" ? `${t("lineDetails")} · ${localName(selectedLine, lang)}` :
          screen.kind === "machine" ? `${t("machineDetails")} · ${localName(selectedMachine, lang)}` :
          screen.kind === "createLine" ? t("addLine") :
          screen.kind === "createMachine" ? t("addMachineShort") :
          screen.kind === "areas" ? t("areasOptional") : t("manageCategories")
        }</h2></div>
      </header>
      {(screen.kind === "line" || screen.kind === "createLine") && <>
        <Configuration key={screen.kind === "line" ? screen.id : "new-line"} {...props} view="lines"
          standalone={{ record: selectedLine || null, blocked: !!draft,
            onSaved: () => props.initialMachineId && props.onBackToFloor
              ? props.onBackToFloor() : setScreen({ kind: "overview" }), onCancel: () => go({ kind: "overview" }) }} />
        {selectedLine && <section className="management-order panel">
          <div className="section-head"><div><h3>{t("machineOrder")}</h3><p>{t("machineOrderHelp")}</p></div>
            <button className="primary" disabled={!draft || busy} onClick={() => void saveLayout()}>{t("saveOrder")}</button></div>
          {draft && <p role="status" className="muted">{t("saveLayoutFirst")}</p>}
          <ol>{ordered(String(selectedLine.id)).map((machine, index, group) => <li key={String(machine.id)}>
            <span className="management-order-index">{index + 1}</span>
            <button className="management-order-name" onClick={() => go({ kind: "machine", id: String(machine.id) })}>{localName(machine, lang)}</button>
            {editable && <div className="row-actions">
              <button aria-label={`${t("moveUp")} ${localName(machine, lang)}`} disabled={index === 0 || busy} onClick={() => move(String(machine.id), String(selectedLine.id), index - 1)}>↑</button>
              <button aria-label={`${t("moveDown")} ${localName(machine, lang)}`} disabled={index === group.length - 1 || busy} onClick={() => move(String(machine.id), String(selectedLine.id), index + 1)}>↓</button>
            </div>}
          </li>)}</ol>
        </section>}
      </>}
      {(screen.kind === "machine" || screen.kind === "createMachine") && <>
        <Configuration key={screen.kind === "machine" ? screen.id : "new-machine"} {...props} view="centers"
          standalone={{ record: savedMachine || null, blocked: !!draft,
            onSaved: () => props.initialMachineId && props.onBackToFloor
              ? props.onBackToFloor() : setScreen({ kind: "overview" }), onCancel: () => go({ kind: "overview" }) }} />
        {selectedMachine && <section className="management-flow-settings panel">
          <div className="section-head"><div><h3>{t("flowSettings")}</h3><p>{t("flowSettingsHelp")}</p></div>
            <button className="primary" disabled={!draft || busy} onClick={() => void saveLayout()}>{t("saveFlowSettings")}</button></div>
          <div className="form-grid">
            <Field label={t("moveTo")}><select value={String(selectedMachine.line_id || "")} disabled={!editable || busy}
              onChange={(e) => move(String(selectedMachine.id), e.target.value, centers.length)}>
              <option value="">{t("independent")}</option>
              {lines.map((line) => <option key={String(line.id)} value={String(line.id)}>{localName(line, lang)}</option>)}
            </select></Field>
            <Field label={t("position")}><div className="management-position">
              <span>{machineIndex + 1} / {machineSiblings.length}</span>
              <button aria-label={t("moveUp")} disabled={!editable || machineIndex <= 0 || busy} onClick={() => move(String(selectedMachine.id), String(selectedMachine.line_id || ""), machineIndex - 1)}>↑</button>
              <button aria-label={t("moveDown")} disabled={!editable || machineIndex >= machineSiblings.length - 1 || busy} onClick={() => move(String(selectedMachine.id), String(selectedMachine.line_id || ""), machineIndex + 1)}>↓</button>
            </div></Field>
            <Field label={t("dependencyMode")}><select value={String(selectedMachine.dependency_mode)} disabled={!editable || !selectedMachine.line_id || busy}
              onChange={(e) => change(centers.map((x) => x.id === selectedMachine.id ? {
                ...x, dependency_mode: e.target.value,
                impact_scope: ["non_blocking", "independent"].includes(e.target.value) ? "none" : x.impact_scope === "none" ? "downstream" : x.impact_scope,
              } : x))}>
              {["blocking", "non_blocking", "independent", "buffer"].map((mode) => <option key={mode} value={mode}>{t(mode)}</option>)}
            </select></Field>
            <Field label={t("impactScope")}><select value={String(["non_blocking", "independent"].includes(String(selectedMachine.dependency_mode)) ? "none" : selectedMachine.impact_scope || "downstream")}
              disabled={!editable || !selectedMachine.line_id || busy}
              onChange={(e) => change(centers.map((x) => x.id === selectedMachine.id ? {
                ...x, impact_scope: e.target.value,
                dependency_mode: e.target.value === "none" ? "non_blocking" : x.dependency_mode === "buffer" ? "buffer" : "blocking",
              } : x))}>
              {["whole_line", "downstream", "none"].map((scope) => <option key={scope} value={scope}>{t(scope)}</option>)}
            </select></Field>
            {selectedMachine.dependency_mode === "buffer" && <Field label={t("bufferMinutes")}><input type="number" min={1} max={10080}
              value={Number(selectedMachine.buffer_minutes)} disabled={!editable || busy}
              onChange={(e) => change(centers.map((x) => x.id === selectedMachine.id ? { ...x, buffer_minutes: Number(e.target.value) } : x))} /></Field>}
          </div>
          {draft && <p role="status" className="muted">{t("saveLayoutFirst")}</p>}
        </section>}
      </>}
      {screen.kind === "areas" && <Configuration {...props} view="factory" />}
      {screen.kind === "categories" && <Configuration {...props} view="work_center_categories" />}
    </>}
  </section>;
}
