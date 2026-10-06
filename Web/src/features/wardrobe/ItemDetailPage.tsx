import type { ReactNode } from 'react'
import { api } from '../../api/client'
import { useResource } from '../../api/useResource'
import { EmptyState, ErrorPanel, Loading } from '../../app/Feedback'
import { useMeta } from '../../app/meta'
import { Link } from '../../app/router'
import { ItemImage } from './ItemImage'

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="field">
      <dt>{label}</dt>
      <dd>{children}</dd>
    </div>
  )
}

function formatDate(value: string | undefined): string {
  return value ? new Date(value).toLocaleString('zh-CN') : '无'
}

/** 单品详情（只读）。编辑功能在后续阶段接入。 */
export function ItemDetailPage({ id }: { id: string }) {
  const meta = useMeta()
  const item = useResource(() => api.item(id), [id])

  if (item.error) {
    return (
      <section className="page">
        {item.error.status === 404 ? (
          <EmptyState title="未找到该单品" description="它可能已被删除。">
            <Link to="/" className="button">
              返回衣橱
            </Link>
          </EmptyState>
        ) : (
          <ErrorPanel error={item.error} onRetry={item.reload} />
        )}
      </section>
    )
  }
  if (!item.data) return <Loading />
  const data = item.data
  const names = (kind: 'scenario' | 'season' | 'warmthLevel', values: string[]) =>
    values.length ? values.map((value) => meta.name(kind, value)).join('、') : '未设置'

  return (
    <section className="page">
      <Link to="/" className="back-link">
        返回衣橱
      </Link>
      <h1 className="page-title">{data.title}</h1>
      <div className="detail">
        <ItemImage item={data} className="detail-image" />
        <dl className="fields">
          <Field label="分类">
            {meta.name('category', data.category)}
            {data.subtype ? ` · ${meta.name('subtype', data.subtype)}` : ''}
          </Field>
          <Field label="状态">{meta.name('status', data.status)}</Field>
          <Field label="适用场景">{names('scenario', data.scenarios)}</Field>
          <Field label="保暖度">
            {data.warmthScore}（{meta.name('warmthLevel', data.warmthLevel)}）
          </Field>
          <Field label="适用季节">{names('season', data.seasons)}</Field>
          <Field label="主色">
            <span className="color-row">
              <span className="swatch" style={{ backgroundColor: data.dominantColor.hex }} />
              {data.dominantColor.name} {data.dominantColor.hex}
            </span>
          </Field>
          {data.secondaryColor && (
            <Field label="辅色">
              <span className="color-row">
                <span className="swatch" style={{ backgroundColor: data.secondaryColor.hex }} />
                {data.secondaryColor.name}
              </span>
            </Field>
          )}
          <Field label="防水">{data.isWaterproof ? '是' : '否'}</Field>
          {data.status === 'inLaundry' && <Field label="入袋时间">{formatDate(data.laundryEntryDate)}</Field>}
          <Field label="品牌">{data.brand || '未填写'}</Field>
          <Field label="备注">{data.notes || '未填写'}</Field>
          <Field label="录入时间">{formatDate(data.createdAt)}</Field>
          <Field label="更新时间">{formatDate(data.updatedAt)}</Field>
        </dl>
      </div>
    </section>
  )
}
