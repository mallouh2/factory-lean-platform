import { useEffect, useRef, useState, type ReactNode } from "react";
import FlowConnector from "./FlowConnector";
import { routeRows } from "@/utils/floor-visual.mjs";
import type { Row } from "@/types";

export default function FactoryRoute({
  machines,
  renderMachine,
  connectorActive,
  connectorTone,
  continuationLabel,
  direction = "ltr",
  minimumCardWidth = 180,
  maximumCardWidth,
  fillLastRow = true,
}: {
  machines: Row[];
  renderMachine: (machine: Row, index: number) => ReactNode;
  connectorActive: (previous: Row, current: Row) => boolean;
  connectorTone?: (previous: Row, current: Row) => "blocked" | "borrowed" | undefined;
  continuationLabel: string;
  direction?: "ltr" | "rtl";
  minimumCardWidth?: number;
  maximumCardWidth?: number;
  fillLastRow?: boolean;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [columns, setColumns] = useState(1);
  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    const measure = () => setColumns(Math.max(1, Math.floor((element.clientWidth + 34) / (minimumCardWidth + 34))));
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, [minimumCardWidth]);
  const rows = routeRows(machines, columns) as Row[][];
  let offset = 0;
  return (
    <div className="ff2-flow" dir={direction} ref={ref}>
      {rows.map((row, rowIndex) => {
        const first = offset;
        offset += row.length;
        return (
          <div className="ff2-route-group" key={String(row[0].id)}>
            {rowIndex > 0 && (
              <div className="ff2-route-continue" aria-label={continuationLabel}>
                <span aria-hidden="true">↳</span>
                <span dir="auto">{continuationLabel}</span>
                <span aria-hidden="true">↓</span>
              </div>
            )}
            <div className="ff2-route-row" style={{ gridTemplateColumns: `repeat(${fillLastRow ? row.length : columns}, minmax(0, 1fr))`,
              maxWidth: maximumCardWidth ? `${row.length * maximumCardWidth + (row.length - 1) * 34}px` : undefined }}>
              {row.map((machine, index) => (
                <div className="ff2-flow-item" key={String(machine.id)}>
                  {renderMachine(machine, first + index)}
                  {index < row.length - 1 && (
                    <FlowConnector active={connectorActive(machine, row[index + 1])} tone={connectorTone?.(machine, row[index + 1])} />
                  )}
                </div>
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
}
