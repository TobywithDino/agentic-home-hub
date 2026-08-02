# -*- coding: utf-8 -*-
"""
Review summary prompt templates.

兩個視角：
- consumer_prompt: 針對某個服務項目，給消費者看的摘要（讓潛在用戶快速了解這個服務的口碑）
- merchant_prompt: 針對商家全部服務的評價，給商家看的經營洞察（幫商家發現優缺點、改善方向）
"""


def build_consumer_prompt(service_name: str, reviews: list[dict]) -> str:
    """
    給消費者看的摘要 prompt。
    重點：正負評平衡、客觀呈現、讓潛在消費者快速判斷是否適合自己。
    """
    review_lines = _format_reviews_for_prompt(reviews)

    return f"""你是一個社區服務評價分析助手。以下是「{service_name}」這個服務項目的用戶評價資料。

請根據這些評價，產生一份給**潛在消費者**閱讀的服務口碑摘要，幫助他們決定是否使用此服務。

## 評價資料

{review_lines}

## 輸出格式要求

請用繁體中文輸出，結構如下：

**整體評分**：（計算平均分並說明，例如：4.2 / 5.0，共 N 筆評價）

**服務亮點**：
- 列出 2~4 個消費者最常提到的正面優點

**注意事項**：
- 列出 1~3 個消費者反映的缺點或需要注意的地方（若無負評可略）

**一句話總結**：
用一句話幫潛在消費者總結是否值得嘗試。

注意：若評價數量不足（少於 3 筆），請說明資料量有限，摘要僅供參考。"""


def build_merchant_prompt(vendor_name: str, reviews: list[dict], week_start: str, week_end: str, service_names: dict[int, str] | None = None) -> str:
    """
    給商家看的 AI 智慧洞察 prompt。
    輸出結構化 JSON，對應 UI 三個區塊：
    - summary:        本週住戶需求 AI 摘要（字串，≤125 字）
    - suggestions:    廠商營運與服務優化建議（3~4 點陣列，每點 ≤20 字）
    - sentiment_stats: 客戶情緒統計（positive / neutral / negative 筆數）

    service_names: {service_id: service_name}，有傳入時評價區塊顯示服務名稱而非 ID
    """
    review_lines = _format_reviews_for_prompt(reviews, service_names=service_names)

    return f"""你是一個社區服務平台的 AI 分析助手。以下是「{vendor_name}」在 {week_start} 至 {week_end} 這一週內收到的客戶評價資料。

## 評價資料

{review_lines}

## 輸出格式要求

**只輸出 JSON，不要有任何其他文字或 markdown 包裝。**

輸出格式如下：
{{
  "summary": "根據本週所有文字評論做一段精簡但具體的摘要（至多 125 字）",
  "suggestions": [
    "「服務態度」平均最低，建議優先改善此環節。",
    "N 筆中立評價代表體驗尚可但未達期待，是最易透過細節優化轉為正面的區間。",
    "第三條建議（根據評價內容給出，≤15 字）",
    "第四條建議（選填，若有明顯問題才加，≤15 字）"
  ],
  "sentiment_stats": {{
    "positive": 正面評價筆數（overall_rating 4~5 分）,
    "neutral": 中立評價筆數（overall_rating 3 分）,
    "negative": 負面評價筆數（overall_rating 1~2 分）
  }}
}}

規則：
1. summary 輸出一段摘要，繁體中文，**至多 125 字**（含標點）
2. suggestions 3~4 點，每點繁體中文，**至多 20 字**（含標點），基於本週評價給出具體可執行的建議
3. sentiment_stats 依 overall_rating 分類：4~5 分為正面、3 分為中立、1~2 分為負面
4. 若本週無任何評價，summary 改為「本週尚無新評價資料。」，suggestions 給通用建議，sentiment_stats 全填 0"""


def _format_reviews_for_prompt(reviews: list[dict], service_names: dict[int, str] | None = None) -> str:
    """將 review 物件陣列格式化成 prompt 裡的純文字區塊。
    service_names: {service_id: name}，有傳入時顯示服務名稱，否則顯示服務ID。
    """
    if not reviews:
        return "（目前無評價資料）"

    lines = []
    for i, r in enumerate(reviews, 1):
        rating = r.get("overall_rating", "N/A")
        content = r.get("review_content") or "（無文字評價）"
        service_id = r.get("service_id")
        cre_time = str(r.get("cre_time", ""))[:10]  # 只取日期部分

        # 服務標籤：有名稱就顯示名稱，否則退回 ID
        if service_names and service_id and service_id in service_names:
            service_label = service_names[service_id]
        else:
            service_label = f"服務ID:{service_id}" if service_id else "未知服務"

        # rating_detail 若有的話也附上
        detail = r.get("rating_detail")
        detail_str = ""
        if detail and isinstance(detail, dict):
            detail_parts = [f"{k}:{v}" for k, v in detail.items()]
            detail_str = f"（細項：{', '.join(detail_parts)}）"

        lines.append(
            f"{i}. [{service_label}] 評分:{rating}/5{detail_str} | {cre_time}\n   評價內容：{content}"
        )

    return "\n\n".join(lines)
