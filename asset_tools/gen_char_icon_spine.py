#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
角色图标 Spine 生成器（5 组件版）

把 assets/image/spine/角色图标/ 下五个分层组件打包成 Spine 4.2 资源
（图集 png + atlas + setup/baked json），并附带导出 scripts/char_icon_partsdata.lua
供编辑器（char_icon_test.lua）实时驱动 / 调参 / 导出。

五张图同尺寸（606×634），同画布分层导出，叠加即原位
→ attachment 偏移补偿后完全还原原始构图。

图层顺序（视觉从上到下）：丝带 > 发尾 > 发丝 > 图案本体 > 三菱形光翼
→ spine slots 数组顺序（先画=底层）：三菱形光翼, 图案本体, 发丝, 发尾, 丝带

动画：
  · 丝带/发尾：绕根部小幅 rotate（横向组件 → 末端上下摆），相位错开
  · 发丝     ：绕根部小幅 rotate（纵向组件 → 末端左右摆）
  · 图案本体 ：静止
  · 三菱形光翼：以图案本体中心为支点，顺时针连续旋转（spine 负角度）

用法：python3 asset_tools/gen_char_icon_spine.py
"""

import json
import math
import os
from PIL import Image
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "assets", "image", "spine", "角色图标")
OUT_DIR = os.path.join(ROOT, "assets", "Spines")
LUA_OUT = os.path.join(ROOT, "scripts", "char_icon_partsdata.lua")

# 组件定义
#   name   : spine 标识（英文，骨骼=b_<name> / slot=<name> / attachment=<name>）
#   disp   : 源文件名（无扩展，也是显示名）
#   kind   : sway(随风摆) / spin(绕本体中心旋转) / static(静止)
#   pivot  : 旋转支点取法 left/right/top/bottom/center/bodycenter
#   anim   : sway → {amp(度), period(秒), phase(弧度)}；spin → {spinPeriod(秒)}
#   tf     : 组件变换默认值（编辑器调好后回填）
#            offX/offY=骨骼位移(spine 坐标), scale=缩放, flipX=水平翻转, alpha=透明度
# 注：anim/tf 默认值取自编辑器实测调优结果，保证工具产出 = 最终资源表现
COMPONENTS = [
    {"name": "guangyi", "disp": "三菱形光翼", "kind": "spin",
     "pivot": "bodycenter", "anim": {"spinPeriod": 18.0},
     "tf": {"offX": 13.0, "offY": -20.0, "scale": 0.95}},
    {"name": "body",    "disp": "图案本体",   "kind": "static",
     "pivot": "center",     "anim": {}},
    {"name": "fasi",    "disp": "发丝",       "kind": "sway",
     "pivot": "top",        "anim": {"amp": 6.0, "period": 3.6, "phase": 0.45}},
    {"name": "fawei",   "disp": "发尾",       "kind": "sway",
     "pivot": "right",      "anim": {"amp": 3.5, "period": 3.6, "phase": 4.4}},
    {"name": "sidai",   "disp": "丝带",       "kind": "sway",
     "pivot": "left",       "anim": {"amp": 4.0, "period": 2.25, "phase": 0.0}},
]
# slots 绘制顺序（自底向上，先=最底层）
DRAW_ORDER = ["guangyi", "body", "fasi", "fawei", "sidai"]
# 图案本体（用于 spin 支点）
BODY_NAME = "body"

ALPHA_THRESH = 16
ATLAS_NAME = "char_icon.png"
JSON_NAME = "char_icon.json"
ATLAS_FILE = "char_icon.atlas"


def alpha_bbox(arr):
    a = arr[:, :, 3]
    ys, xs = np.where(a > ALPHA_THRESH)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def pivot_pixel(rule, bbox, W, H, body_center):
    """根据规则返回旋转支点（图像坐标 px,py）。"""
    minx, miny, maxx, maxy = bbox
    cx, cy = (minx + maxx) // 2, (miny + maxy) // 2
    if rule == "left":
        return minx, cy
    if rule == "right":
        return maxx, cy
    if rule == "top":
        return cx, miny
    if rule == "bottom":
        return cx, maxy
    if rule == "center":
        return W // 2, H // 2
    if rule == "bodycenter":
        return body_center
    return cx, cy


def main():
    # 1) 读图、校验同尺寸
    imgs, W, H = {}, None, None
    for c in COMPONENTS:
        im = Image.open(os.path.join(SRC_DIR, c["disp"] + ".png")).convert("RGBA")
        if W is None:
            W, H = im.size
        elif im.size != (W, H):
            raise SystemExit("组件尺寸不一致: %s %s != %dx%d" % (c["disp"], im.size, W, H))
        imgs[c["name"]] = im

    # 2) 合成图集（横向并排，全幅）
    n = len(COMPONENTS)
    atlas_w, atlas_h = W * n, H
    atlas_img = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))
    region = {}
    for i, c in enumerate(COMPONENTS):
        atlas_img.paste(imgs[c["name"]], (i * W, 0))
        region[c["name"]] = (i * W, 0)
    atlas_img.save(os.path.join(OUT_DIR, ATLAS_NAME))

    # 3) bbox / 整体包围盒 / 本体中心
    bboxes, overall = {}, [W, H, 0, 0]
    for c in COMPONENTS:
        bb = alpha_bbox(np.array(imgs[c["name"]]))
        bboxes[c["name"]] = bb
        if bb:
            overall[0] = min(overall[0], bb[0]); overall[1] = min(overall[1], bb[1])
            overall[2] = max(overall[2], bb[2]); overall[3] = max(overall[3], bb[3])
    bbb = bboxes[BODY_NAME]
    body_center = ((bbb[0] + bbb[2]) // 2, (bbb[1] + bbb[3]) // 2)

    cx_canvas, cy_canvas = W / 2.0, H / 2.0

    def to_spine_y(iy):
        return H - iy

    # 4) atlas 文件
    lines = [ATLAS_NAME, "size: %d, %d" % (atlas_w, atlas_h),
             "format: RGBA8888", "filter: Linear, Linear", "repeat: none"]
    for c in COMPONENTS:
        ax, ay = region[c["name"]]
        lines += [c["name"], "  rotate: false",
                  "  xy: %d, %d" % (ax, ay),
                  "  size: %d, %d" % (W, H),
                  "  orig: %d, %d" % (W, H),
                  "  offset: 0, 0", "  index: -1"]
    with open(os.path.join(OUT_DIR, ATLAS_FILE), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    # 5) 计算每组件 骨骼位置(bx,by) / attachment 偏移(Vx,Vy)
    meta = {}  # name -> dict
    for c in COMPONENTS:
        px, py = pivot_pixel(c["pivot"], bboxes[c["name"]], W, H, body_center)
        bx = float(px)
        by = float(to_spine_y(py))
        Vx = round(cx_canvas - px, 3)
        Vy = round(py - cy_canvas, 3)
        tf = c.get("tf", {})
        meta[c["name"]] = {"bx": bx, "by": by, "Vx": Vx, "Vy": Vy,
                           "kind": c["kind"], "disp": c["disp"], "anim": c["anim"],
                           "offX": float(tf.get("offX", 0.0)), "offY": float(tf.get("offY", 0.0)),
                           "scale": float(tf.get("scale", 1.0)), "flipX": bool(tf.get("flipX", False)),
                           "alpha": float(tf.get("alpha", 1.0))}

    # 6) 动画时长（= spin 周期，保证连续旋转无缝循环）
    spin_period = 12.0
    for c in COMPONENTS:
        if c["kind"] == "spin":
            spin_period = float(c["anim"].get("spinPeriod", 12.0))
            break
    anim_dur = spin_period

    def sway_keys(amp, period, phase):
        cycles = max(1, round(anim_dur / period))   # 取整 → 无缝循环
        N = 24
        kf = []
        for i in range(N + 1):
            v = amp * math.sin(2 * math.pi * cycles * (i / N) + phase)
            d = {"value": round(v, 3)}
            if i > 0:
                d["time"] = round(anim_dur * i / N, 3)
            kf.append(d)
        return kf

    def spin_keys():
        N = 48
        kf = []
        for i in range(N + 1):
            v = -360.0 * (i / N)                     # 顺时针(负角度)，0→-360 无缝
            d = {"value": round(v, 3), "curve": "linear"}
            if i > 0:
                d["time"] = round(anim_dur * i / N, 3)
            kf.append(d)
        return kf

    # 7) 组装 json
    bones = [{"name": "root"}]
    slots = []
    attachments = {}
    anim_bones = {}
    for c in COMPONENTS:
        nm = c["name"]; m = meta[nm]
        b = {"name": "b_" + nm, "parent": "root",
             "x": round(m["bx"] + m["offX"], 3), "y": round(m["by"] + m["offY"], 3)}
        if m["scale"] != 1.0 or m["flipX"]:
            b["scaleX"] = round((-1.0 if m["flipX"] else 1.0) * m["scale"], 3)
            b["scaleY"] = round(m["scale"], 3)
        bones.append(b)
        attachments[nm] = {nm: {"x": m["Vx"], "y": m["Vy"], "width": W, "height": H}}
        if c["kind"] == "sway":
            anim_bones["b_" + nm] = {"rotate": sway_keys(
                c["anim"]["amp"], c["anim"]["period"], c["anim"]["phase"])}
        elif c["kind"] == "spin":
            anim_bones["b_" + nm] = {"rotate": spin_keys()}
    for nm in DRAW_ORDER:
        m = meta[nm]
        s = {"name": nm, "bone": "b_" + nm, "attachment": nm}
        if m["alpha"] < 0.999:
            s["color"] = "ffffff%02x" % int(m["alpha"] * 255 + 0.5)
        slots.append(s)

    skel = {"hash": "chariconspine5", "spine": "4.2.00",
            "x": 0.0, "y": 0.0, "width": float(W), "height": float(H),
            "images": "./", "audio": ""}
    obj = {
        "skeleton": skel,
        "bones": bones,
        "slots": slots,
        "skins": [{"name": "default", "attachments": attachments}],
        "animations": {"idle": {"bones": anim_bones}},
    }
    with open(os.path.join(OUT_DIR, JSON_NAME), "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False)

    # 8) 导出 partsdata.lua（编辑器读取，parts 按 DRAW_ORDER = slots 顺序）
    def lua_part(nm):
        m = meta[nm]
        a = m["anim"]
        if m["kind"] == "sway":
            anim = "amp=%.1f, period=%.2f, phase=%.3f, spinPeriod=0," % (
                a["amp"], a["period"], a["phase"])
        elif m["kind"] == "spin":
            anim = "amp=0, period=0, phase=0, spinPeriod=%.2f," % a.get("spinPeriod", 12.0)
        else:
            anim = "amp=0, period=0, phase=0, spinPeriod=0,"
        tf = ("offX=%.1f, offY=%.1f, scale=%.3f, flipX=%s, alpha=%.3f," % (
            m["offX"], m["offY"], m["scale"], "true" if m["flipX"] else "false", m["alpha"]))
        return ('    {name="%s", disp="%s", kind="%s", bx=%.1f, by=%.1f, '
                'Vx=%.1f, Vy=%.1f, w=%d, h=%d, %s %s},') % (
            nm, m["disp"], m["kind"], m["bx"], m["by"], m["Vx"], m["Vy"], W, H, anim, tf)

    lua = ["-- AUTO-GENERATED by gen_char_icon_spine.py — 角色图标 Spine 组件元数据",
           "-- 图层顺序(自底向上): " + ", ".join(DRAW_ORDER),
           "return {",
           "  W=%d, H=%d, atlasW=%d, atlasH=%d, atlasImage=\"%s\"," % (
               W, H, atlas_w, atlas_h, ATLAS_NAME),
           "  src=\"Spines/%s\"," % JSON_NAME,
           "  animDur=%.2f," % anim_dur,
           "  bounds={x=0, y=0, w=%d, h=%d}," % (W, H),
           "  parts={"]
    for nm in DRAW_ORDER:
        lua.append(lua_part(nm))
    lua += ["  },", "}", ""]
    with open(LUA_OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lua))

    print("生成完成：")
    print("  图集 :", os.path.join(OUT_DIR, ATLAS_NAME), "(%dx%d)" % (atlas_w, atlas_h))
    print("  atlas:", os.path.join(OUT_DIR, ATLAS_FILE))
    print("  json :", os.path.join(OUT_DIR, JSON_NAME))
    print("  parts:", LUA_OUT)
    print("  body center(图像坐标):", body_center, " anim_dur=%.1fs" % anim_dur)
    print("  slots(底→顶):", DRAW_ORDER)
    for nm in DRAW_ORDER:
        m = meta[nm]
        print("    %-8s kind=%-6s bone=(%.0f,%.0f) V=(%.0f,%.0f)" % (
            nm, m["kind"], m["bx"], m["by"], m["Vx"], m["Vy"]))


if __name__ == "__main__":
    main()
