import { useEffect, useState } from 'react'

// Default the picker to the next whole hour: the common case is "book the next
// free slot", and nobody wants to type a date to do it.
function nextHourLocal() {
  const d = new Date()
  d.setMinutes(0, 0, 0)
  d.setHours(d.getHours() + 1)
  const pad = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

export default function NewAppointmentModal({ doctors, patients, onClose, onCreate }) {
  const [form, setForm] = useState({
    patient_id: '',
    doctor_id: '',
    scheduled_at: nextHourLocal(),
    duration_minutes: 30,
    reason: '',
  })
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  const submit = async (e) => {
    e.preventDefault()
    setError(null)
    setBusy(true)
    try {
      await onCreate({
        patient_id: Number(form.patient_id),
        doctor_id: Number(form.doctor_id),
        // datetime-local has no timezone. toISOString() attaches the browser's
        // real offset, which is what the API requires -- it rejects naive
        // datetimes rather than guessing UTC.
        scheduled_at: new Date(form.scheduled_at).toISOString(),
        duration_minutes: Number(form.duration_minutes),
        reason: form.reason || null,
      })
      onClose()
    } catch (err) {
      setError(err.message)
    } finally {
      setBusy(false)
    }
  }

  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value })

  return (
    <div className="modal__backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h2>New appointment</h2>
        <form onSubmit={submit}>
          <label>
            Patient
            <select required value={form.patient_id} onChange={set('patient_id')}>
              <option value="">Select a patient…</option>
              {patients.map((p) => (
                <option key={p.id} value={p.id}>{p.name}</option>
              ))}
            </select>
          </label>
          <label>
            Doctor
            <select required value={form.doctor_id} onChange={set('doctor_id')}>
              <option value="">Select a doctor…</option>
              {doctors.map((d) => (
                <option key={d.id} value={d.id}>{d.name} — {d.specialty}</option>
              ))}
            </select>
          </label>
          <div className="form__row">
            <label>
              When
              <input type="datetime-local" required value={form.scheduled_at} onChange={set('scheduled_at')} />
            </label>
            <label>
              Minutes
              <input type="number" min="5" max="240" step="5" value={form.duration_minutes} onChange={set('duration_minutes')} />
            </label>
          </div>
          <label>
            Reason
            <input type="text" maxLength={500} placeholder="Follow-up, blood work…" value={form.reason} onChange={set('reason')} />
          </label>

          {error && <p className="form__error" role="alert">{error}</p>}

          <div className="modal__actions">
            <button type="button" className="btn btn--ghost" onClick={onClose}>Cancel</button>
            <button type="submit" className="btn btn--primary" disabled={busy}>
              {busy ? 'Booking…' : 'Book appointment'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
