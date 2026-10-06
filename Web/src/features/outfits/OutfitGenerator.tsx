import { useState } from 'react'
import { api, ApiError } from '../../api/client'
import type { ApiSuggestion, ApiSuggestions } from '../../api/types'
import { EmptyState, ErrorPanel, Loading } from '../../app/Feedback'
import { useDataVersion } from '../../app/dataVersion'
import { useMeta } from '../../app/meta'
import { useToast } from '../../app/toast'
import { ChipSingle } from '../../components/Chips'
import { OutfitDraftCard } from './OutfitDraftCard'
import { toMembers } from './outfitSlots'

interface Generated {
  suggestions: ApiSuggestions
  warmth: string
  scenario: string
}

/**
 * 智能生成，对应 App 的 OutfitGeneratorView。算法在服务端共享核心中运行。
 * 收藏时记录生成这批草稿时的条件。App 记录的是点击收藏时界面上的条件，
 * 生成后再改条件会让记录与草稿不符，与 Outfit.targetScenario「生成时的目标场景」的定义矛盾。
 */
export function OutfitGenerator() {
  const meta = useMeta()
  const toast = useToast()
  const { invalidate } = useDataVersion()
  const [warmth, setWarmth] = useState('mild')
  const [scenario, setScenario] = useState('casual')
  const [requireWaterproof, setRequireWaterproof] = useState(false)
  const [generated, setGenerated] = useState<Generated | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<ApiError | null>(null)
  const [busy, setBusy] = useState(false)

  async function generate() {
    setLoading(true)
    setError(null)
    try {
      const suggestions = await api.suggestions({ warmth, scenario, requireWaterproof })
      setGenerated({ suggestions, warmth, scenario })
    } catch (e) {
      setError(e instanceof ApiError ? e : new ApiError(0, 'unknown', String(e)))
    } finally {
      setLoading(false)
    }
  }

  async function act(action: () => Promise<unknown>, message: string) {
    setBusy(true)
    try {
      await action()
      toast(message)
      invalidate()
    } catch (e) {
      toast(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  function favorite(draft: ApiSuggestion, conditions: Generated) {
    return act(
      () =>
        api.createOutfit({
          source: 'generated',
          targetScenario: conditions.scenario,
          targetWarmthLevel: conditions.warmth,
          members: toMembers(draft.members),
        }),
      '已加入收藏',
    )
  }

  function wear(draft: ApiSuggestion) {
    return act(() => api.wear(toMembers(draft.members)), '已设为今天穿这套')
  }

  return (
    <div className="stack">
      <div className="panel stack">
        <div>
          <h2 className="field-title">保暖 / 体感</h2>
          <ChipSingle label="保暖 / 体感" options={meta.meta.warmthLevels} value={warmth} onChange={setWarmth} />
        </div>
        <div>
          <h2 className="field-title">场景</h2>
          <ChipSingle label="场景" options={meta.meta.scenarios} value={scenario} onChange={setScenario} />
        </div>
        <label className="toggle">
          <input type="checkbox" checked={requireWaterproof} onChange={(event) => setRequireWaterproof(event.target.checked)} />
          雨 / 雪天（强制防水外套与鞋子）
        </label>
        <button type="button" className="button button-primary button-block" onClick={generate} disabled={loading}>
          生成穿搭
        </button>
      </div>

      {error ? (
        <ErrorPanel error={error} onRetry={generate} />
      ) : loading ? (
        <Loading label="正在生成…" />
      ) : !generated ? (
        <p className="muted center">选择上方条件后点「生成穿搭」。</p>
      ) : generated.suggestions.missingRequired.length > 0 ? (
        <EmptyState
          title="缺少必选单品，无法生成"
          description={`当前条件下缺少：${generated.suggestions.missingRequired.map((c) => meta.name('category', c)).join('、')}。请先在衣橱补充对应单品。`}
        />
      ) : generated.suggestions.drafts.length === 0 ? (
        <EmptyState title="没有匹配的穿搭" description="没有同时满足该温度与场景的组合，换个条件试试。" />
      ) : (
        <div className="draft-list">
          {generated.suggestions.drafts.map((draft) => (
            <OutfitDraftCard
              key={draft.id}
              members={draft.members}
              busy={busy}
              onFavorite={() => favorite(draft, generated)}
              onWear={() => wear(draft)}
            />
          ))}
        </div>
      )}
    </div>
  )
}
