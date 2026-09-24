import { useEffect, useRef, useState, type ReactNode } from "react";
import FlowConnector from "./FlowConnector";
import { routeRows } from "@/utils/floor-visual.mjs";
import type { Row } from "@/types";

export default function FactoryRoute({
  machines,
  renderMachine,
  connectorActive,
  continuationLabel,
}: {
  machines: Row[];
  renderMachine: (machine: Row, index: number) => ReactNode;
  connectorActive: (previous: Row, current: Row) => boolean;
  continuationLabel: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [columns, setColumns] = useState(1);
  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    const measure = () => setColumns(Math.max(1, Math.floor((element.clientWidth + 34) / 214)));
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  const rows = routeRows(machines, columns) as Row[][];
  let offset = 0;
  return (
    <div className="ff2-flow" dir="ltr" ref={ref}>
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
            <div className="ff2-route-row" style={{ gridTemplateColumns: `repeat(${row.length}, minmax(0, 1fr))` }}>
              {row.map((machine, index) => (
                <div className="ff2-flow-item" key={String(machine.id)}>
                  {renderMachine(machine, first + index)}
                  {index < row.length - 1 && (
                    <FlowConnector active={connectorActive(machine, row[index + 1])} />
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
