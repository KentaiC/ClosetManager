import { EmptyState } from '../../app/Feedback'
import { Link } from '../../app/router'

/** 地址不对应任何页面。 */
export function NotFoundPage() {
  return (
    <section className="page">
      <h1 className="page-title">页面不存在</h1>
      <EmptyState title="没有找到这个页面" description="地址可能有误。">
        <Link to="/" className="button">
          返回衣橱
        </Link>
      </EmptyState>
    </section>
  )
}
