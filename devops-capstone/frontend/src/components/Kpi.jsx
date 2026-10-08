export default function Kpi({ label, value, hint, tone = 'default' }) {
  return (
    <div className={`kpi kpi--${tone}`}>
      <div className="kpi__label">{label}</div>
      <div className="kpi__value">{value}</div>
      {hint && <div className="kpi__hint">{hint}</div>}
    </div>
  )
}
