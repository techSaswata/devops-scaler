const LABEL = {
  scheduled: 'Scheduled',
  completed: 'Completed',
  cancelled: 'Cancelled',
  no_show: 'No show',
}

export default function StatusBadge({ status }) {
  return <span className={`badge badge--${status}`}>{LABEL[status] ?? status}</span>
}
