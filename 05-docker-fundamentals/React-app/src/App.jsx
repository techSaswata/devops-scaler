import { useEffect, useState } from 'react'

export default function App() {
  // A tiny piece of state, so the page proves React is actually running
  // and hydrating — not just serving pre-rendered HTML.
  const [count, setCount] = useState(0)
  const [mountedAt, setMountedAt] = useState('')

  useEffect(() => {
    setMountedAt(new Date().toLocaleTimeString())
  }, [])

  return (
    <div className="card">
      <div className="badge">● React</div>
      <h1>
        Hello <span>World</span>
      </h1>
      <p className="sub">
        A React single-page app, built with Vite and served as static files by
        Nginx from a multi-stage Docker image.
      </p>

      <button className="btn" onClick={() => setCount((c) => c + 1)}>
        Clicked {count} {count === 1 ? 'time' : 'times'}
      </button>
      <p className="hint">
        The counter is React state — if it increments, the JS bundle really is running.
      </p>

      <dl>
        <dt>Library</dt>
        <dd>React 18</dd>
        <dt>Bundler</dt>
        <dd>Vite 5</dd>
        <dt>Served by</dt>
        <dd>nginx:alpine</dd>
        <dt>Port</dt>
        <dd>80 → published on 3005</dd>
        <dt>Mounted at</dt>
        <dd>{mountedAt || '…'}</dd>
      </dl>

      <p className="foot">Saswata Das · 24BCS10248 · DevOps Homework</p>
    </div>
  )
}
