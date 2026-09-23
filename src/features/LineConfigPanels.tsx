import { useEffect } from "react";
import Configuration from "./Configuration";
import type { FeatureProps } from "./types";
export type PanelKey = "line" | "machine" | "areas" | "categories";
export type PanelsState = {
  line: boolean;
  machine: boolean;
  areas: boolean;
  categories?: boolean;
};
/**
 * The single source of the create/edit record panels, shared by the classic
 * LineBuilder and Factory Floor V2. Opening a panel while a layout draft exists
 * still asks for confirmation before discarding the draft.
 */
export default function LineConfigPanels({
  draft,
  panels,
  setPanels,
  onDiscardDraft,
  requestOpen,
  onRequestHandled,
  ...props
}: FeatureProps & {
  draft: boolean;
  panels: PanelsState;
  setPanels: (updater: (p: PanelsState) => PanelsState) => void;
  onDiscardDraft: () => void;
  requestOpen?: PanelKey | null;
  onRequestHandled?: () => void;
}) {
  const { t } = props;
  function openPanel(key: PanelKey) {
    if (draft) {
      if (!confirm(t("discardChanges"))) return;
      onDiscardDraft();
    }
    setPanels((p) => ({ ...p, [key]: true }));
    requestAnimationFrame(() => {
      document
        .getElementById(`config-panel-${key}`)
        ?.scrollIntoView({ block: "center" });
    });
  }
  useEffect(() => {
    if (requestOpen) {
      openPanel(requestOpen);
      onRequestHandled?.();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [requestOpen]);
  const guardSummary =
    (key: PanelKey) => (e: React.MouseEvent<HTMLElement>) => {
      if (draft) {
        e.preventDefault();
        openPanel(key);
      }
    };
  // React 19 can dispatch the commit-path toggle with a null currentTarget;
  // read the element once, synchronously, and keep state when it is absent.
  const toggle =
    (key: PanelKey) =>
    (e: React.SyntheticEvent<HTMLDetailsElement>) => {
      const open = e.currentTarget?.open;
      setPanels((p) => ({ ...p, [key]: open ?? p[key] }));
    };
  return (
    <>
      <details
        id="config-panel-line"
        className="panel"
        open={panels.line}
        onToggle={toggle("line")}
      >
        <summary onClick={guardSummary("line")}>{t("createLine")}</summary>
        <Configuration {...props} view="lines" />
      </details>
      <details
        id="config-panel-machine"
        className="panel"
        open={panels.machine}
        onToggle={toggle("machine")}
      >
        <summary onClick={guardSummary("machine")}>{t("addMachine")}</summary>
        <Configuration {...props} view="centers" />
      </details>
      <details
        id="config-panel-areas"
        className="panel"
        open={panels.areas}
        onToggle={toggle("areas")}
      >
        <summary onClick={guardSummary("areas")}>{t("areasOptional")}</summary>
        <Configuration {...props} view="factory" />
      </details>
      {props.can("centers", "create") && (
        <details
          id="config-panel-categories"
          className="panel"
          open={panels.categories}
          onToggle={toggle("categories")}
        >
          <summary onClick={guardSummary("categories")}>
            {t("manageCategories")}
          </summary>
          <Configuration {...props} view="work_center_categories" />
        </details>
      )}
    </>
  );
}
