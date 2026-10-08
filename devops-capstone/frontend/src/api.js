// Every call is same-origin: nginx (container) or the Ingress (Kubernetes)
// forwards /api to the backend. Nothing here knows a backend hostname, so the
// built bundle is identical in every environment.
const BASE = '/api'

async function request(path, options = {}) {
  const res = await fetch(`${BASE}${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  })
  if (!res.ok) {
    let detail = `${res.status} ${res.statusText}`
    try {
      const body = await res.json()
      if (body.detail) detail = typeof body.detail === 'string' ? body.detail : JSON.stringify(body.detail)
    } catch {
      /* response had no JSON body; the status line is all we have */
    }
    const err = new Error(detail)
    err.status = res.status
    throw err
  }
  return res.status === 204 ? null : res.json()
}

export const api = {
  stats: () => request('/appointments/stats'),
  appointments: (status) =>
    request(`/appointments${status && status !== 'all' ? `?status=${status}` : ''}`),
  createAppointment: (body) =>
    request('/appointments', { method: 'POST', body: JSON.stringify(body) }),
  updateAppointment: (id, body) =>
    request(`/appointments/${id}`, { method: 'PUT', body: JSON.stringify(body) }),
  deleteAppointment: (id) => request(`/appointments/${id}`, { method: 'DELETE' }),
  doctors: () => request('/doctors'),
  createDoctor: (body) => request('/doctors', { method: 'POST', body: JSON.stringify(body) }),
  patients: () => request('/patients'),
  createPatient: (body) => request('/patients', { method: 'POST', body: JSON.stringify(body) }),
}
