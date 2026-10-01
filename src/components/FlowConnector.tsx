/**
 * Reusable connector between two adjacent machines. Renders a calm line with a
 * small flow indicator that travels along it (~2s loop) only while production
 * actually flows; interrupted flow renders a static, muted connector.
 */
export default function FlowConnector({ active, tone }: { active: boolean; tone?: "blocked" | "borrowed" }) {
  return (
    <span
      className={`ff2-connector${active ? " ff2-flowing" : ""}${tone ? ` ff2-connector-${tone}` : ""}`}
      aria-hidden="true"
    >
      <span className="ff2-connector-line" />
      <span className="ff2-connector-dot" />
      <span className="ff2-connector-arrow" />
    </span>
  );
}
