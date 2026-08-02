import { useCallback } from 'react'
import { Plus, Trash2, GripVertical, ChevronDown, ChevronUp } from 'lucide-react'
import {
  FIELD_INPUT_TYPE_LABELS,
  TYPES_WITH_OPTIONS,
  type FormField,
  type FieldInputType,
} from '@/api'

/** 題目型別下拉選單，順序對應後端 type 代碼 1~10 */
const INPUT_TYPE_ORDER: FieldInputType[] = [
  'short_text',
  'long_text',
  'single_choice',
  'multi_choice',
  'region',
  'photo',
  'remark',
  'contact',
  'date',
  'contact_no_address',
]

export const INPUT_TYPE_OPTIONS = INPUT_TYPE_ORDER.map((value) => ({
  value,
  label: FIELD_INPUT_TYPE_LABELS[value],
}))

/** 不需要 placeholder（題目說明）的型別 */
const TYPES_WITHOUT_PLACEHOLDER: FieldInputType[] = ['region', 'photo', 'date']

/** 編輯器內部的欄位表示。_key 僅供 React 使用，不傳給後端 */
export interface EditableField {
  _key: string
  label: string
  inputType: FieldInputType
  required: boolean
  placeholder: string
  options: string[]
  /** 後端 topic.id。存回時帶上代表更新既有題目，undefined 代表新增 */
  topicId?: number
  /** 後端 topic.form_group_id，用於還原題目原本所屬的題組 */
  groupId?: number
}

export function fieldToEditable(f: FormField): EditableField {
  return {
    _key: f.id,
    label: f.label,
    inputType: f.inputType,
    required: f.required,
    placeholder: f.placeholder ?? '',
    options: f.options ?? [],
    topicId: f.topicId,
    groupId: f.groupId,
  }
}

export function makeEmptyField(): EditableField {
  return {
    _key: `new-${Date.now()}-${Math.random().toString(36).slice(2, 5)}`,
    label: '',
    inputType: 'short_text',
    required: false,
    placeholder: '',
    options: [],
  }
}

/** 將編輯器欄位轉為 api 層需要的 payload 形狀 */
export function editableFieldsToPayload(fields: EditableField[]) {
  return fields.map(({ label, inputType, required, placeholder, options, topicId, groupId }) => ({
    label,
    inputType,
    required,
    placeholder: placeholder || undefined,
    options: TYPES_WITH_OPTIONS.includes(inputType) ? options.filter(Boolean) : undefined,
    topicId,
    groupId,
  }))
}

// ─── 單一欄位編輯列 ─────────────────────────────────────────

interface FieldRowProps {
  field: EditableField
  index: number
  total: number
  onChange: (key: string, patch: Partial<EditableField>) => void
  onRemove: (key: string) => void
  onMove: (key: string, direction: 'up' | 'down') => void
}

export function FieldRow({ field, index, total, onChange, onRemove, onMove }: FieldRowProps) {
  const inputClass =
    'w-full rounded-md border border-slate-300 px-2.5 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-slate-900 focus:border-transparent'

  const hasOptions = TYPES_WITH_OPTIONS.includes(field.inputType)

  const handleOptionChange = (optIdx: number, value: string) => {
    const next = [...field.options]
    next[optIdx] = value
    onChange(field._key, { options: next })
  }

  const addOption = () => onChange(field._key, { options: [...field.options, ''] })
  const removeOption = (optIdx: number) =>
    onChange(field._key, { options: field.options.filter((_, i) => i !== optIdx) })

  return (
    <div className="border border-slate-200 rounded-lg p-3 bg-slate-50 space-y-2">
      {/* 標題列：拖曳把手、欄位標籤輸入、移動按鈕、刪除按鈕 */}
      <div className="flex items-center gap-2">
        <GripVertical className="h-4 w-4 text-slate-400 shrink-0" aria-hidden="true" />

        <input
          type="text"
          value={field.label}
          onChange={(e) => onChange(field._key, { label: e.target.value })}
          placeholder={`欄位 ${index + 1} 名稱`}
          className={`${inputClass} flex-1`}
          aria-label={`欄位 ${index + 1} 名稱`}
        />

        <div className="flex gap-1 shrink-0">
          <button
            type="button"
            onClick={() => onMove(field._key, 'up')}
            disabled={index === 0}
            aria-label="上移"
            className="p-1 rounded hover:bg-slate-200 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
          >
            <ChevronUp className="h-4 w-4" />
          </button>
          <button
            type="button"
            onClick={() => onMove(field._key, 'down')}
            disabled={index === total - 1}
            aria-label="下移"
            className="p-1 rounded hover:bg-slate-200 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
          >
            <ChevronDown className="h-4 w-4" />
          </button>
          <button
            type="button"
            onClick={() => onRemove(field._key)}
            aria-label="刪除此欄位"
            className="p-1 rounded hover:bg-red-100 text-red-500 transition-colors"
          >
            <Trash2 className="h-4 w-4" />
          </button>
        </div>
      </div>

      {/* 第二列：輸入類型、是否必填、題目說明 */}
      <div className="flex items-center gap-3 pl-6">
        <div className="flex items-center gap-1.5">
          <label className="text-xs text-slate-500 whitespace-nowrap">類型</label>
          <select
            value={field.inputType}
            onChange={(e) =>
              onChange(field._key, {
                inputType: e.target.value as FieldInputType,
                options: [],
              })
            }
            className="rounded-md border border-slate-300 px-2 py-1 text-xs focus:outline-none focus:ring-2 focus:ring-slate-900"
          >
            {INPUT_TYPE_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </select>
        </div>

        <label className="flex items-center gap-1.5 cursor-pointer text-xs text-slate-600">
          <input
            type="checkbox"
            checked={field.required}
            onChange={(e) => onChange(field._key, { required: e.target.checked })}
            className="rounded border-slate-300 text-slate-900 focus:ring-slate-900"
          />
          必填
        </label>

        {!TYPES_WITHOUT_PLACEHOLDER.includes(field.inputType) && (
          <input
            type="text"
            value={field.placeholder}
            onChange={(e) => onChange(field._key, { placeholder: e.target.value })}
            placeholder="題目說明（選填）"
            className="flex-1 rounded-md border border-slate-300 px-2.5 py-1 text-xs focus:outline-none focus:ring-2 focus:ring-slate-900"
          />
        )}
      </div>

      {/* 選項清單（僅單選／複選）*/}
      {hasOptions && (
        <div className="pl-6 space-y-1.5">
          <p className="text-xs text-slate-500">選項清單</p>
          {field.options.map((opt, optIdx) => (
            <div key={optIdx} className="flex items-center gap-2">
              <input
                type="text"
                value={opt}
                onChange={(e) => handleOptionChange(optIdx, e.target.value)}
                placeholder={`選項 ${optIdx + 1}`}
                className="flex-1 rounded-md border border-slate-300 px-2.5 py-1 text-xs focus:outline-none focus:ring-2 focus:ring-slate-900"
              />
              <button
                type="button"
                onClick={() => removeOption(optIdx)}
                aria-label={`刪除選項 ${optIdx + 1}`}
                className="p-1 rounded hover:bg-red-100 text-red-400 transition-colors"
              >
                <Trash2 className="h-3.5 w-3.5" />
              </button>
            </div>
          ))}
          <button
            type="button"
            onClick={addOption}
            className="text-xs text-slate-600 hover:text-slate-900 hover:underline"
          >
            ＋ 新增選項
          </button>
        </div>
      )}
    </div>
  )
}

// ─── 欄位清單編輯器（含新增按鈕與排序邏輯）──────────────────

interface FieldListEditorProps {
  fields: EditableField[]
  onFieldsChange: (next: EditableField[]) => void
  /** 新增按鈕文字 */
  addLabel?: string
}

/**
 * 題目欄位清單編輯器
 *
 * 把增／刪／改／排序邏輯集中在此，讓「服務管理總覽」的新增服務 Modal
 * 與「表單內容修改」頁面共用同一份行為，不需各自實作一遍。
 */
export function FieldListEditor({
  fields,
  onFieldsChange,
  addLabel = '新增欄位',
}: FieldListEditorProps) {
  const handleChange = useCallback(
    (key: string, patch: Partial<EditableField>) => {
      onFieldsChange(fields.map((f) => (f._key === key ? { ...f, ...patch } : f)))
    },
    [fields, onFieldsChange]
  )

  const handleRemove = useCallback(
    (key: string) => {
      onFieldsChange(fields.filter((f) => f._key !== key))
    },
    [fields, onFieldsChange]
  )

  const handleMove = useCallback(
    (key: string, direction: 'up' | 'down') => {
      const idx = fields.findIndex((f) => f._key === key)
      if (idx < 0) return
      const swapIdx = direction === 'up' ? idx - 1 : idx + 1
      if (swapIdx < 0 || swapIdx >= fields.length) return
      const next = [...fields]
      ;[next[idx], next[swapIdx]] = [next[swapIdx], next[idx]]
      onFieldsChange(next)
    },
    [fields, onFieldsChange]
  )

  return (
    <div>
      <div className="space-y-2">
        {fields.map((field, index) => (
          <FieldRow
            key={field._key}
            field={field}
            index={index}
            total={fields.length}
            onChange={handleChange}
            onRemove={handleRemove}
            onMove={handleMove}
          />
        ))}
      </div>

      <button
        type="button"
        onClick={() => onFieldsChange([...fields, makeEmptyField()])}
        className="mt-3 w-full rounded-lg border-2 border-dashed border-slate-300 py-2.5 text-sm text-slate-500 hover:border-slate-400 hover:text-slate-700 hover:bg-slate-50 transition-colors flex items-center justify-center gap-1.5"
      >
        <Plus className="h-4 w-4" />
        {addLabel}
      </button>
    </div>
  )
}
