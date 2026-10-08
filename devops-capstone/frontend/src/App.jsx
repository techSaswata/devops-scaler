import { useCallback, useEffect, useState } from 'react'
import { api } from './api.js'
import Kpi from './components/Kpi.jsx'
import StatusBadge from './components/StatusBadge.jsx'
import NewAppointmentModal from './components/NewAppointmentModal.jsx'

const FILTERS = ['all', 'scheduled', 'completed', 'cancelled', 'no_show']

function whenLabel(iso) {
  const d = new Date(iso)
  return d.toLocaleString(undefined, {
    weekday: 'short', day: 'numeric', month: 'short',
    hour: '2-digit', minute: '2-digit',
  })
}

export default function App() {
  const [stats, setStats] = useState(null)
  const [appointments, setAppointments] = useState([])
  const [doctors, setDoctors] = useState([])
  const [patients, setPatients] = useState([])
  const [filter, setFilter] = useState('all')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [modalOpen, setModalOpen] = useState(false)

  const load = useCallback(async () => {
    setError(null)
    try {
      const [s, a, d, p] = await Promise.all([
        api.stats(), api.appointments(filter), api.doctors(), api.patients(),
      ])
      setStats(s); setAppointments(a); setDoctors(d); setPatients(p)
    } catch (err) {
      // The backend being unreachable is a normal state during a rollout, so
      // it gets a real message rather than a blank screen.
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }, [filter])

  useEffect(() => { load() }, [load])

  const setStatus = async (id, status) => {
    await api.updateAppointment(id, { status })
    load()
  }
  const remove = async (id) => {
    await api.deleteAppointment(id)
    load()
  }

  return (
    <div className="app">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand__mark">CF</span>
          <span className="brand__name">ClinicFlow</span>
        </div>
        <nav className="nav">
          <a className="nav__item nav__item--active" href="#dashboard">Dashboard</a>
          <a className="nav__item" href="#appointments">Appointments</a>
          <a className="nav__item" href="#doctors">Doctors</a>
          <a className="nav__item" href="#patients">Patients</a>
        </nav>
        <div className="sidebar__foot">
          <div className="sidebar__meta">{doctors.length} doctors</div>
          <div className="sidebar__meta">{patients.length} patients</div>
        </div>
      </aside>

      <main className="main">
        <header className="header">
          <div>
            <h1>Appointments</h1>
            <p className="header__sub">Front desk overview</p>
          </div>
          <button className="btn btn--primary" onClick={() => setModalOpen(true)}>
            + New appointment
          </button>
        </header>

        {error && (
          <div className="banner banner--error" role="alert">
            <strong>Cannot reach the API.</strong> {error}
            <button className="btn btn--ghost btn--sm" onClick={load}>Retry</button>
          </div>
        )}

        <section className="kpis">
          <Kpi label="Total" value={stats?.total ?? '—'} />
          <Kpi label="Scheduled" value={stats?.scheduled ?? '—'} tone="blue" />
          <Kpi label="Next 7 days" value={stats?.upcoming_7_days ?? '—'} tone="amber" />
          <Kpi label="Completed" value={stats?.completed ?? '—'} tone="green" />
          <Kpi
            label="Completion rate"
            value={stats ? `${stats.completion_rate}%` : '—'}
            hint="completed ÷ (completed + no-show)"
          />
        </section>

        <div className="filters">
          {FILTERS.map((f) => (
            <button
              key={f}
              className={`chip ${filter === f ? 'chip--active' : ''}`}
              onClick={() => setFilter(f)}
            >
              {f === 'no_show' ? 'no show' : f}
            </button>
          ))}
        </div>

        <section className="card">
          {loading ? (
            <p className="empty">Loading…</p>
          ) : appointments.length === 0 ? (
            <p className="empty">No appointments match this filter.</p>
          ) : (
            <table className="table">
              <thead>
                <tr>
                  <th>When</th><th>Patient</th><th>Doctor</th>
                  <th>Reason</th><th>Status</th><th aria-label="actions" />
                </tr>
              </thead>
              <tbody>
                {appointments.map((a) => (
                  <tr key={a.id}>
                    <td className="nowrap">{whenLabel(a.scheduled_at)}<span className="muted"> · {a.duration_minutes}m</span></td>
                    <td>{a.patient_name}</td>
                    <td>{a.doctor_name}</td>
                    <td className="muted">{a.reason || '—'}</td>
                    <td><StatusBadge status={a.status} /></td>
                    <td className="row-actions">
                      {a.status === 'scheduled' && (
                        <>
                          <button className="btn btn--sm" onClick={() => setStatus(a.id, 'completed')}>Complete</button>
                          <button className="btn btn--sm" onClick={() => setStatus(a.id, 'no_show')}>No show</button>
                          <button className="btn btn--sm btn--ghost" onClick={() => setStatus(a.id, 'cancelled')}>Cancel</button>
                        </>
                      )}
                      <button className="btn btn--sm btn--danger" onClick={() => remove(a.id)}>Delete</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      </main>

      {modalOpen && (
        <NewAppointmentModal
          doctors={doctors}
          patients={patients}
          onClose={() => setModalOpen(false)}
          onCreate={async (body) => { await api.createAppointment(body); await load() }}
        />
      )}
    </div>
  )
}
