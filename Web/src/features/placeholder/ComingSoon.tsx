import { EmptyState } from '../../app/Feedback'

/** 尚未迁移的页面占位，对应 App 的 ComingSoonView。 */
export function ComingSoon({ title }: { title: string }) {
  return (
    <section className="page">
      <h1 className="page-title">{title}</h1>
      <EmptyState title="此页面正在迁移" description="对应的功能会在后续阶段接入 Web 版。" />
    </section>
  )
}
