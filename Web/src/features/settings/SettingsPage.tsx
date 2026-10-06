import { useEffect, useState, type FormEvent } from 'react'
import { api } from '../../api/client'
import type { ApiProfile } from '../../api/types'
import { useResource } from '../../api/useResource'
import { ACCENTS, MODES, applyAppearance, loadAppearance, saveAppearance, type Appearance } from '../../app/appearance'
import { ErrorPanel, Loading } from '../../app/Feedback'
import { useMeta } from '../../app/meta'
import { Link } from '../../app/router'
import { useToast } from '../../app/toast'

function ProfileForm({ initial }: { initial: ApiProfile }) {
  const meta = useMeta()
  const toast = useToast()
  const [profile, setProfile] = useState(initial)
  const [saving, setSaving] = useState(false)

  async function submit(event: FormEvent) {
    event.preventDefault()
    setSaving(true)
    try {
      setProfile(await api.updateProfile(profile))
      toast('已保存')
    } catch (e) {
      toast(e instanceof Error ? e.message : String(e))
    } finally {
      setSaving(false)
    }
  }

  const number = (value: string) => (value === '' ? 0 : Number(value))
  return (
    <form className="form" onSubmit={submit} aria-label="个人资料">
      <fieldset>
        <legend>个人资料</legend>
        <label className="form-row">
          <span>身高（cm）</span>
          <input type="number" min={0} step="0.1" value={profile.heightCm} onChange={(e) => setProfile({ ...profile, heightCm: number(e.target.value) })} />
        </label>
        <label className="form-row">
          <span>体重（kg）</span>
          <input type="number" min={0} step="0.1" value={profile.weightKg} onChange={(e) => setProfile({ ...profile, weightKg: number(e.target.value) })} />
        </label>
        <label className="form-row">
          <span>年龄</span>
          <input type="number" min={0} max={120} step={1} value={profile.age} onChange={(e) => setProfile({ ...profile, age: number(e.target.value) })} />
        </label>
        <label className="form-row">
          <span>性别</span>
          <select value={profile.gender} onChange={(e) => setProfile({ ...profile, gender: e.target.value })}>
            {meta.meta.genders.map((option) => (
              <option key={option.value} value={option.value}>
                {option.displayName}
              </option>
            ))}
          </select>
        </label>
        <p className="hint">仅存储于本机，用于后续「衣橱补充智能建议」。</p>
        <div className="form-actions">
          <button type="submit" className="button button-primary" disabled={saving}>
            保存
          </button>
        </div>
      </fieldset>
    </form>
  )
}

function AppearanceForm() {
  const [appearance, setAppearance] = useState<Appearance>(loadAppearance)
  useEffect(() => {
    applyAppearance(appearance)
    saveAppearance(appearance)
  }, [appearance])
  return (
    <fieldset className="form">
      <legend>外观自定义</legend>
      <div className="form-row">
        <span>强调色</span>
        <div className="chips chips-wrap" role="radiogroup" aria-label="强调色">
          {ACCENTS.map((option) => (
            <button
              key={option.value}
              type="button"
              role="radio"
              aria-checked={appearance.accent === option.value}
              className={`chip${appearance.accent === option.value ? ' selected' : ''}`}
              onClick={() => setAppearance({ ...appearance, accent: option.value })}
            >
              <span className="swatch" style={{ backgroundColor: option.color }} /> {option.label}
            </button>
          ))}
        </div>
      </div>
      <label className="form-row">
        <span>外观模式</span>
        <select value={appearance.mode} onChange={(e) => setAppearance({ ...appearance, mode: e.target.value as Appearance['mode'] })}>
          {MODES.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
      </label>
      <label className="form-row">
        <span>卡片圆角：{appearance.cornerRadius}</span>
        <input type="range" min={0} max={28} step={1} value={appearance.cornerRadius}
          onChange={(e) => setAppearance({ ...appearance, cornerRadius: Number(e.target.value) })} />
      </label>
      <p className="hint">自定义只保存在当前浏览器，不影响核心交互；强调色与外观模式即时生效。</p>
    </fieldset>
  )
}

/** 设置页，对应 App 的 SettingsView。数据备份与「清理相似衣物」在阶段 5 接入。 */
export function SettingsPage() {
  const profile = useResource(() => api.profile(), [])
  return (
    <section className="page">
      <h1 className="page-title">设置</h1>
      {profile.error ? <ErrorPanel error={profile.error} onRetry={profile.reload} /> : profile.data ? <ProfileForm initial={profile.data} /> : <Loading />}
      <AppearanceForm />
      <fieldset className="form">
        <legend>工具</legend>
        <ul className="link-list">
          <li><Link to="/travel">差旅打包</Link></li>
        </ul>
      </fieldset>
    </section>
  )
}
