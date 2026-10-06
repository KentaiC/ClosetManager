import { api } from '../../api/client'
import { useDataVersion } from '../../app/dataVersion'
import { Link, navigate } from '../../app/router'
import { useToast } from '../../app/toast'
import { ItemEditor } from '../wardrobe/ItemEditor'

/** 单件录入，对应 App 的 ItemEditorView 新增模式：保存后回到衣橱。 */
export function NewItemPage() {
  const { invalidate } = useDataVersion()
  const toast = useToast()
  return (
    <section className="page">
      <Link to="/" className="back-link">
        返回衣橱
      </Link>
      <h1 className="page-title">新增单品</h1>
      <ItemEditor
        onSubmit={(update) => api.createItem(update)}
        onCancel={() => navigate('/')}
        onSaved={() => {
          invalidate()
          toast('已添加')
          navigate('/')
        }}
      />
    </section>
  )
}
