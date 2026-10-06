import { useState } from 'react'
import { api } from '../../api/client'
import type { ApiTravelPlan } from '../../api/types'
import { useResource } from '../../api/useResource'
import { ErrorPanel } from '../../app/Feedback'
import { useDataVersion } from '../../app/dataVersion'
import { useMeta } from '../../app/meta'
import { useToast } from '../../app/toast'
import { ItemThumbnails } from '../../components/ItemThumbnails'

/** 差旅打包，对应 App 的 TravelCapsuleView。数量规则与打包建议都由服务端按共享核心计算。 */
export function TravelPage() {
  const meta = useMeta()
  const toast = useToast()
  const { version, invalidate } = useDataVersion()
  const [days, setDays] = useState(3)
  const [warmth, setWarmth] = useState('mild')
  const [scenario, setScenario] = useState('casual')
  const [plan, setPlan] = useState<ApiTravelPlan | null>(null)
  const counts = useResource(() => api.travelPlan({ days, warmth, scenario }), [days])
  const packed = useResource(() => api.items({ status: 'inLuggage' }), [version])

  async function suggest() {
    try {
      const result = await api.travelPlan({ days, warmth, scenario })
      setPlan(result)
      if (result.suggestion.length === 0) toast('可用单品不足，换个条件试试')
    } catch (e) {
      toast(e instanceof Error ? e.message : String(e))
    }
  }

  async function pack() {
    if (!plan) return
    try {
      await api.pack(plan.suggestion.map((item) => item.id))
      toast('已装入行李箱')
      setPlan(null)
      invalidate()
    } catch (e) {
      toast(e instanceof Error ? e.message : String(e))
    }
  }

  async function unpack() {
    try {
      await api.unpackAll()
      toast('已结束差旅，全部取出')
      invalidate()
    } catch (e) {
      toast(e instanceof Error ? e.message : String(e))
    }
  }

  const info = counts.data
  return (
    <section className="page">
      <h1 className="page-title">差旅打包</h1>
      <fieldset className="form">
        <legend>行程</legend>
        <label className="form-row">
          <span>旅行天数：{days} 天</span>
          <input type="number" min={1} max={30} value={days} onChange={(e) => setDays(Math.min(30, Math.max(1, Number(e.target.value) || 1)))} />
        </label>
        <label className="form-row">
          <span>目标温度</span>
          <select value={warmth} onChange={(e) => setWarmth(e.target.value)}>
            {meta.meta.warmthLevels.map((o) => <option key={o.value} value={o.value}>{o.displayName}</option>)}
          </select>
        </label>
        <label className="form-row">
          <span>场景</span>
          <select value={scenario} onChange={(e) => setScenario(e.target.value)}>
            {meta.meta.scenarios.map((o) => <option key={o.value} value={o.value}>{o.displayName}</option>)}
          </select>
        </label>
      </fieldset>

      <fieldset className="form" data-testid="essentials">
        <legend>基础携带</legend>
        {counts.error ? (
          <ErrorPanel error={counts.error} onRetry={counts.reload} />
        ) : info ? (
          <>
            <p>内裤 / 打底：{info.underwearCount} 条</p>
            <p>袜子：{info.socksCount} 双</p>
            <p className="hint">
              {info.showsCapHint ? `预计长途旅行有洗衣条件，内裤携带已封顶 ${info.packingCap} 条。` : '规则：每天 1 条 + 1 条备用。'}
            </p>
          </>
        ) : null}
      </fieldset>

      <fieldset className="form">
        <legend>推荐打包</legend>
        <button type="button" className="button" onClick={suggest}>按行程生成打包建议</button>
        {plan && plan.suggestion.length > 0 && (
          <>
            <ItemThumbnails items={plan.suggestion} size={72} />
            <button type="button" className="button button-primary" onClick={pack}>
              一键装入行李箱（{plan.suggestion.length} 件）
            </button>
          </>
        )}
      </fieldset>

      {(packed.data ?? []).length > 0 && (
        <fieldset className="form" data-testid="luggage">
          <legend>行李箱（{packed.data!.length} 件）</legend>
          <ItemThumbnails items={packed.data!} />
          <button type="button" className="button button-danger" onClick={unpack}>结束差旅，全部取出</button>
        </fieldset>
      )}
    </section>
  )
}
