# -*- coding: utf-8 -*-
"""
F. 表單結構 API（對應 API_Reference.md #41-65）
pms_form, pms_form_group, pms_form_topic, pms_topic_media, pms_topic_option,
pms_topic_county_district_relation
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import PageParams, page_params
from app.models import (
    PmsForm,
    PmsFormGroup,
    PmsFormTopic,
    PmsTopicCountyDistrictRelation,
    PmsTopicMedia,
    PmsTopicOption,
)
from app.schemas import (
    CountyDistrictRelationCreate,
    CountyDistrictRelationDelete,
    CountyDistrictRelationOut,
    FormCreate,
    FormGroupCreate,
    FormGroupOut,
    FormGroupUpdate,
    FormOut,
    FormReviewUpdate,
    FormTopicCreate,
    FormTopicOut,
    FormTopicUpdate,
    FormUpdate,
    PagedResponse,
    TopicMediaCreate,
    TopicMediaOut,
    TopicOptionCreate,
    TopicOptionOut,
    TopicOptionUpdate,
)
from app.utils import SYSTEM_ACTOR_ID, now_utc, paginate

router = APIRouter(tags=["forms"])


def _get_form_or_404(db: Session, form_id: int) -> PmsForm:
    obj = db.get(PmsForm, form_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="表單不存在")
    return obj


def _get_topic_or_404(db: Session, topic_id: int) -> PmsFormTopic:
    obj = db.get(PmsFormTopic, topic_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="題目不存在")
    return obj


# --- pms_form ------------------------------------------------------------------
@router.get("/forms", response_model=PagedResponse)
def list_forms(
    service_vendor_id: int | None = None,
    type: str | None = None,
    db: Session = Depends(get_db),
    pp: PageParams = Depends(page_params),
):
    stmt = select(PmsForm).where(PmsForm.is_deleted == "0").order_by(PmsForm.id)
    if service_vendor_id is not None:
        stmt = stmt.where(PmsForm.service_vendor_id == service_vendor_id)
    if type is not None:
        stmt = stmt.where(PmsForm.type == type)
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[FormOut.model_validate(i) for i in items])


@router.get("/forms/{form_id}", response_model=FormOut)
def get_form(form_id: int, db: Session = Depends(get_db)):
    return _get_form_or_404(db, form_id)


@router.get("/forms/{form_id}/full")
def get_form_full(form_id: int, db: Session = Depends(get_db)):
    """組裝完整表單結構(group+topic+option+media+county關聯)，供APP填單頁渲染。"""
    form = _get_form_or_404(db, form_id)
    groups = db.execute(
        select(PmsFormGroup).where(PmsFormGroup.form_id == form_id).order_by(PmsFormGroup.sort)
    ).scalars().all()
    topics = db.execute(
        select(PmsFormTopic).where(PmsFormTopic.form_id == form_id).order_by(PmsFormTopic.sort)
    ).scalars().all()
    topic_ids = [t.id for t in topics]
    medias = []
    options = []
    relations = []
    if topic_ids:
        medias = db.execute(
            select(PmsTopicMedia).where(PmsTopicMedia.topic_id.in_(topic_ids)).order_by(PmsTopicMedia.sort)
        ).scalars().all()
        options = db.execute(
            select(PmsTopicOption).where(PmsTopicOption.topic_id.in_(topic_ids)).order_by(PmsTopicOption.sort)
        ).scalars().all()
        relations = db.execute(
            select(PmsTopicCountyDistrictRelation).where(PmsTopicCountyDistrictRelation.topic_id.in_(topic_ids))
        ).scalars().all()

    media_by_topic: dict[int, list] = {}
    for m in medias:
        media_by_topic.setdefault(m.topic_id, []).append(TopicMediaOut.model_validate(m))
    option_by_topic: dict[int, list] = {}
    for o in options:
        option_by_topic.setdefault(o.topic_id, []).append(TopicOptionOut.model_validate(o))
    relation_by_topic: dict[int, list] = {}
    for r in relations:
        relation_by_topic.setdefault(r.topic_id, []).append(CountyDistrictRelationOut.model_validate(r))

    topics_out = []
    for t in topics:
        topic_dict = FormTopicOut.model_validate(t).model_dump()
        topic_dict["media"] = media_by_topic.get(t.id, [])
        topic_dict["options"] = option_by_topic.get(t.id, [])
        topic_dict["county_district_relations"] = relation_by_topic.get(t.id, [])
        topics_out.append(topic_dict)

    return {
        "form": FormOut.model_validate(form),
        "groups": [FormGroupOut.model_validate(g) for g in groups],
        "topics": topics_out,
    }


@router.post("/forms", response_model=FormOut, status_code=201)
def create_form(payload: FormCreate, db: Session = Depends(get_db)):
    now = now_utc()
    obj = PmsForm(
        service_vendor_id=payload.service_vendor_id, type=payload.type, sub_type=payload.sub_type,
        name=payload.name, intro_content=payload.intro_content, notice_content=payload.notice_content,
        terms_content=payload.terms_content, review_status="0", reviewed_id=None, reviewed_time=None,
        is_enable=payload.is_enable, is_deleted="0", upd_time=now, cre_time=now,
        upd_id=None, cre_id=SYSTEM_ACTOR_ID, feature=payload.feature,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.patch("/forms/{form_id}", response_model=FormOut)
def update_form(form_id: int, payload: FormUpdate, db: Session = Depends(get_db)):
    obj = _get_form_or_404(db, form_id)
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(obj, field, value)
    obj.upd_time = now_utc()
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/forms/{form_id}", status_code=204)
def delete_form(form_id: int, db: Session = Depends(get_db)):
    obj = _get_form_or_404(db, form_id)
    obj.is_deleted = "1"
    obj.upd_time = now_utc()
    db.commit()


@router.patch("/forms/{form_id}/review", response_model=FormOut)
def review_form(form_id: int, payload: FormReviewUpdate, db: Session = Depends(get_db)):
    """窄範圍審核端點，僅可更新 review_status/reviewed_id/reviewed_time。"""
    obj = _get_form_or_404(db, form_id)
    obj.review_status = payload.review_status
    obj.reviewed_id = payload.reviewed_id
    obj.reviewed_time = now_utc()
    obj.upd_time = now_utc()
    db.commit()
    db.refresh(obj)
    return obj


# --- pms_form_group --------------------------------------------------------------
@router.get("/forms/{form_id}/groups", response_model=PagedResponse)
def list_form_groups(form_id: int, db: Session = Depends(get_db), pp: PageParams = Depends(page_params)):
    _get_form_or_404(db, form_id)
    stmt = select(PmsFormGroup).where(PmsFormGroup.form_id == form_id).order_by(PmsFormGroup.sort)
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[FormGroupOut.model_validate(i) for i in items])


@router.post("/forms/{form_id}/groups", response_model=FormGroupOut, status_code=201)
def create_form_group(form_id: int, payload: FormGroupCreate, db: Session = Depends(get_db)):
    _get_form_or_404(db, form_id)
    now = now_utc()
    obj = PmsFormGroup(
        form_id=form_id, name=payload.name, sort=payload.sort,
        upd_time=now, cre_time=now, upd_id=None, cre_id=SYSTEM_ACTOR_ID, feature=payload.feature,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.patch("/form-groups/{form_group_id}", response_model=FormGroupOut)
def update_form_group(form_group_id: int, payload: FormGroupUpdate, db: Session = Depends(get_db)):
    obj = db.get(PmsFormGroup, form_group_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="題組不存在")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(obj, field, value)
    obj.upd_time = now_utc()
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/form-groups/{form_group_id}", status_code=204)
def delete_form_group(form_group_id: int, db: Session = Depends(get_db)):
    """pms_form_group 無 is_deleted 欄位，採實體刪除。"""
    obj = db.get(PmsFormGroup, form_group_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="題組不存在")
    db.delete(obj)
    db.commit()


# --- pms_form_topic --------------------------------------------------------------
@router.get("/forms/{form_id}/topics", response_model=PagedResponse)
def list_form_topics(form_id: int, db: Session = Depends(get_db), pp: PageParams = Depends(page_params)):
    _get_form_or_404(db, form_id)
    stmt = select(PmsFormTopic).where(PmsFormTopic.form_id == form_id).order_by(PmsFormTopic.sort)
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[FormTopicOut.model_validate(i) for i in items])


@router.post("/forms/{form_id}/topics", response_model=FormTopicOut, status_code=201)
def create_form_topic(form_id: int, payload: FormTopicCreate, db: Session = Depends(get_db)):
    _get_form_or_404(db, form_id)
    now = now_utc()
    obj = PmsFormTopic(
        form_id=form_id, **payload.model_dump(),
        upd_time=now, cre_time=now, upd_id=None, cre_id=SYSTEM_ACTOR_ID,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.patch("/form-topics/{topic_id}", response_model=FormTopicOut)
def update_form_topic(topic_id: int, payload: FormTopicUpdate, db: Session = Depends(get_db)):
    obj = _get_topic_or_404(db, topic_id)
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(obj, field, value)
    obj.upd_time = now_utc()
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/form-topics/{topic_id}", status_code=204)
def delete_form_topic(topic_id: int, db: Session = Depends(get_db)):
    """pms_form_topic 無 is_deleted 欄位，採實體刪除。"""
    obj = _get_topic_or_404(db, topic_id)
    db.delete(obj)
    db.commit()


# --- pms_topic_media --------------------------------------------------------------
@router.get("/form-topics/{topic_id}/media", response_model=PagedResponse)
def list_topic_media(topic_id: int, db: Session = Depends(get_db), pp: PageParams = Depends(page_params)):
    _get_topic_or_404(db, topic_id)
    stmt = select(PmsTopicMedia).where(PmsTopicMedia.topic_id == topic_id).order_by(PmsTopicMedia.sort)
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[TopicMediaOut.model_validate(i) for i in items])


@router.post("/form-topics/{topic_id}/media", response_model=TopicMediaOut, status_code=201)
def create_topic_media(topic_id: int, payload: TopicMediaCreate, db: Session = Depends(get_db)):
    topic = _get_topic_or_404(db, topic_id)
    now = now_utc()
    obj = PmsTopicMedia(
        form_id=topic.form_id, topic_id=topic_id, img_url=payload.img_url, sort=payload.sort,
        upd_time=now, cre_time=now, upd_id=None, cre_id=SYSTEM_ACTOR_ID,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/topic-media/{media_id}", status_code=204)
def delete_topic_media(media_id: int, db: Session = Depends(get_db)):
    obj = db.get(PmsTopicMedia, media_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="圖片不存在")
    db.delete(obj)
    db.commit()


# --- pms_topic_option --------------------------------------------------------------
@router.get("/form-topics/{topic_id}/options", response_model=PagedResponse)
def list_topic_options(topic_id: int, db: Session = Depends(get_db), pp: PageParams = Depends(page_params)):
    _get_topic_or_404(db, topic_id)
    stmt = select(PmsTopicOption).where(PmsTopicOption.topic_id == topic_id).order_by(PmsTopicOption.sort)
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[TopicOptionOut.model_validate(i) for i in items])


@router.post("/form-topics/{topic_id}/options", response_model=TopicOptionOut, status_code=201)
def create_topic_option(topic_id: int, payload: TopicOptionCreate, db: Session = Depends(get_db)):
    topic = _get_topic_or_404(db, topic_id)
    now = now_utc()
    obj = PmsTopicOption(
        form_id=topic.form_id, topic_id=topic_id, **payload.model_dump(),
        upd_time=now, cre_time=now, upd_id=None, cre_id=SYSTEM_ACTOR_ID,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.patch("/topic-options/{option_id}", response_model=TopicOptionOut)
def update_topic_option(option_id: int, payload: TopicOptionUpdate, db: Session = Depends(get_db)):
    obj = db.get(PmsTopicOption, option_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="選項不存在")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(obj, field, value)
    obj.upd_time = now_utc()
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/topic-options/{option_id}", status_code=204)
def delete_topic_option(option_id: int, db: Session = Depends(get_db)):
    obj = db.get(PmsTopicOption, option_id)
    if obj is None:
        raise HTTPException(status_code=404, detail="選項不存在")
    db.delete(obj)
    db.commit()


# --- pms_topic_county_district_relation ------------------------------------------
@router.get("/form-topics/{topic_id}/county-district-relations", response_model=PagedResponse)
def list_topic_county_district_relations(
    topic_id: int, db: Session = Depends(get_db), pp: PageParams = Depends(page_params)
):
    _get_topic_or_404(db, topic_id)
    stmt = select(PmsTopicCountyDistrictRelation).where(
        PmsTopicCountyDistrictRelation.topic_id == topic_id
    )
    items, total = paginate(db, stmt, pp)
    return PagedResponse(total=total, limit=pp.limit, offset=pp.offset,
                          items=[CountyDistrictRelationOut.model_validate(i) for i in items])


@router.post(
    "/form-topics/{topic_id}/county-district-relations",
    response_model=CountyDistrictRelationOut,
    status_code=201,
)
def create_topic_county_district_relation(
    topic_id: int, payload: CountyDistrictRelationCreate, db: Session = Depends(get_db)
):
    topic = _get_topic_or_404(db, topic_id)
    now = now_utc()
    obj = PmsTopicCountyDistrictRelation(
        form_id=topic.form_id, topic_id=topic_id,
        eff_ts_from=payload.eff_ts_from, eff_ts_to=payload.eff_ts_to,
        county_code=payload.county_code, district_code=payload.district_code,
        upd_time=now, cre_time=now, upd_id=None, cre_id=SYSTEM_ACTOR_ID,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/form-topics/{topic_id}/county-district-relations", status_code=204)
def delete_topic_county_district_relation(
    topic_id: int, payload: CountyDistrictRelationDelete, db: Session = Depends(get_db)
):
    """複合主鍵資源(form_id+topic_id+eff_ts_from+county_code+district_code)，
    無單一id可用於路徑，故以 request body 帶完整key組合進行刪除。"""
    topic = _get_topic_or_404(db, topic_id)
    obj = db.get(
        PmsTopicCountyDistrictRelation,
        (topic.form_id, topic_id, payload.eff_ts_from, payload.county_code, payload.district_code),
    )
    if obj is None:
        raise HTTPException(status_code=404, detail="對應關係不存在")
    db.delete(obj)
    db.commit()
