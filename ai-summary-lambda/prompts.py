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


def build_merchant_prompt(vendor_name: str, reviews: list[dict]) -> str:
    """
    給商家看的經營洞察 prompt。
    重點：找出服務痛點、挖掘改善機會、分析各服務項目差異。
    """
    review_lines = _format_reviews_for_prompt(reviews)

    return f"""你是一個社區服務平台的商業分析助手。以下是「{vendor_name}」這家服務商旗下所有服務項目的用戶評價資料。

請根據這些評價，產生一份給**商家經營者**閱讀的評價洞察報告，幫助他們了解目前服務品質與改善方向。

## 評價資料

{review_lines}

## 輸出格式要求

請用繁體中文輸出，結構如下：

**整體表現**：（整體平均分、評價總數、各服務項目評分分佈概況）

**優勢項目**：
- 列出評分最高或正面評價最多的服務項目及其亮點

**待改善項目**：
- 列出評分較低或客訴較多的服務項目，並引用具體評價內容說明原因

**顧客聲音關鍵字**：
- 列出最常出現的正面關鍵字（3~5 個）
- 列出最常出現的負面關鍵字（3~5 個，若無可略）

**改善建議**：
- 針對待改善項目提出 2~3 個具體可執行的建議

注意：若某服務項目評價數量不足（少於 3 筆），個別分析僅供參考，請標注。"""


def _format_reviews_for_prompt(reviews: list[dict]) -> str:
    """將 review 物件陣列格式化成 prompt 裡的純文字區塊。"""
    if not reviews:
        return "（目前無評價資料）"

    lines = []
    for i, r in enumerate(reviews, 1):
        rating = r.get("overall_rating", "N/A")
        content = r.get("review_content") or "（無文字評價）"
        service_id = r.get("service_id", "")
        cre_time = str(r.get("cre_time", ""))[:10]  # 只取日期部分

        # rating_detail 若有的話也附上
        detail = r.get("rating_detail")
        detail_str = ""
        if detail and isinstance(detail, dict):
            detail_parts = [f"{k}:{v}" for k, v in detail.items()]
            detail_str = f"（細項：{', '.join(detail_parts)}）"

        lines.append(
            f"{i}. [服務ID:{service_id}] 評分:{rating}/5{detail_str} | {cre_time}\n   評價內容：{content}"
        )

    return "\n\n".join(lines)
