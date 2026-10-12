# -*- coding: utf-8 -*-
"""上板功能自动验证 v2：对照实验（运动帧 vs 静止帧），输出检出率/误检率/帧率/证据帧"""
import cv2
import numpy as np
import time
import json
import os

# 证据输出：仓库 board/logs/（脚本位于 build/scripts/，上溯两级到仓库根）
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "board", "logs")
os.makedirs(OUT, exist_ok=True)
N_FRAMES = 120         # 采样帧数（约4秒）
MOTION_TH = 1.5        # 帧间灰度差均值阈值：>1.5=画面在动

cap = cv2.VideoCapture(1)
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
if not cap.isOpened():
    print('ERROR: 打不开采集卡')
    exit(1)

def detect_red_boxes(frame, min_side=40, min_area=100):
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    m1 = cv2.inRange(hsv, (0, 50, 40), (12, 255, 255))
    m2 = cv2.inRange(hsv, (160, 50, 40), (180, 255, 255))
    mask = (m1 | m2).astype(np.uint8)
    num, labels, stats, centroids = cv2.connectedComponentsWithStats(mask, 8)
    boxes = []
    for i in range(1, num):
        x, y, w, h = (int(stats[i, cv2.CC_STAT_LEFT]), int(stats[i, cv2.CC_STAT_TOP]),
                      int(stats[i, cv2.CC_STAT_WIDTH]), int(stats[i, cv2.CC_STAT_HEIGHT]))
        area = int(stats[i, cv2.CC_STAT_AREA])
        if w >= min_side and h >= min_side and area >= min_area and area < 0.5 * w * h:
            boxes.append([x, y, w, h])
    return boxes

results = []
frame_count = 0
prev_gray = None
first_box_frame = None
t0 = time.time()
for i in range(N_FRAMES):
    ok, frame = cap.read()
    if not ok:
        print(f'第{i}帧读取失败')
        break
    frame_count += 1
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    motion = 0.0
    if prev_gray is not None:
        motion = float(cv2.absdiff(gray, prev_gray).mean())
    prev_gray = gray
    boxes = detect_red_boxes(frame)
    bright = float(np.mean(frame))
    results.append({'boxes': boxes, 'bright': bright, 'motion': motion})
    if boxes and first_box_frame is None:
        first_box_frame = frame.copy()
cap.release()
elapsed = time.time() - t0
fps = frame_count / elapsed if elapsed > 0 else 0

# 对照统计
motion_frames = [r for r in results if r['motion'] > MOTION_TH]
still_frames = [r for r in results if r['motion'] <= MOTION_TH]
tp = sum(1 for r in motion_frames if r['boxes'])      # 有运动且有框
fn = sum(1 for r in motion_frames if not r['boxes'])  # 有运动无框（漏检）
fp = sum(1 for r in still_frames if r['boxes'])       # 无运动有框（误检）
tn = sum(1 for r in still_frames if not r['boxes'])
det_rate = tp / len(motion_frames) * 100 if motion_frames else 0
fa_rate = fp / len(still_frames) * 100 if still_frames else 0

# 运动量分层：轻运动(1.5-3) / 中运动(3-5) / 强运动(>5)
def layer_rate(lo, hi):
    frames = [r for r in results if lo < r['motion'] <= hi]
    if not frames:
        return None, 0
    hit = sum(1 for r in frames if r['boxes'])
    return hit / len(frames) * 100, len(frames)

l1, n1 = layer_rate(MOTION_TH, 3)
l2, n2 = layer_rate(3, 5)
l3, n3 = layer_rate(5, 999)
brights = [r['bright'] for r in results]
avg_bright = sum(brights) / len(brights) if brights else 0
box_counts = [len(r['boxes']) for r in results if r['boxes']]
last_boxes = results[-1]['boxes'] if results else []
mot_avg = sum(r['motion'] for r in results) / len(results)

print(f'=== 上板功能验证 v2（{frame_count} 帧，{elapsed:.1f}s，{fps:.1f} fps）===')
print(f'画面亮度均值: {avg_bright:.1f}')
print(f'画面平均运动量: {mot_avg:.2f}（阈值 {MOTION_TH}）')
print(f'运动帧: {len(motion_frames)}  静止帧: {len(still_frames)}')
print(f'--- 对照结果 ---')
print(f'检出率（有运动时有框）: {det_rate:.0f}%  ({tp}/{len(motion_frames)})')
print(f'误检率（静止时也有框）: {fa_rate:.0f}%  ({fp}/{len(still_frames)})')
print(f'--- 运动量分层检出率 ---')
print(f'轻运动(1.5-3): {l1:.0f}%  ({n1}帧)' if l1 is not None else f'轻运动: 无帧')
print(f'中运动(3-5):   {l2:.0f}%  ({n2}帧)' if l2 is not None else f'中运动: 无帧')
print(f'强运动(>5):    {l3:.0f}%  ({n3}帧)' if l3 is not None else f'强运动: 无帧')
if box_counts:
    print(f'红框数量: 平均 {sum(box_counts)/len(box_counts):.1f} 个/帧（范围 {min(box_counts)}-{max(box_counts)}）')
print(f'最后一帧: {"有框 " + str(last_boxes) if last_boxes else "无框"}')

# 判定
print('=== 判定 ===')
if avg_bright < 8:
    print('FAIL: 画面全黑，板子没收到输入信号')
elif len(motion_frames) == 0:
    print('WARN: 采样期间画面无运动（视频可能在暂停/静止）→ 换运动中的视频重测')
elif det_rate >= 80 and fa_rate <= 20:
    print(f'PASS: 检测功能正常 — 检出率 {det_rate:.0f}%（≥80%），误检率 {fa_rate:.0f}%（≤20%）')
elif det_rate < 80:
    print(f'FAIL: 漏检偏多 — 检出率仅 {det_rate:.0f}%（有运动 {len(motion_frames)} 帧中只框住 {tp} 帧）')
elif fa_rate > 20:
    print(f'WARN: 误检偏多 — 静止 {len(still_frames)} 帧中有 {fp} 帧出现红框（误检率 {fa_rate:.0f}%）')

# 存证据帧（优先存有框的）
ev = first_box_frame
if ev is None:
    cap = cv2.VideoCapture(1)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    ok, ev = cap.read()
    cap.release()
if ev is not None:
    cv2.imwrite(f'{OUT}\\evidence_frame.jpg', ev)
    print('证据帧已存: evidence_frame.jpg')

# 存原始数据（供报告引用）
with open(f'{OUT}\\verify_result.json', 'w', encoding='utf-8') as f:
    json.dump({
        'fps': round(fps, 1), 'avg_bright': round(avg_bright, 1),
        'motion_th': MOTION_TH, 'motion_frames': len(motion_frames),
        'still_frames': len(still_frames), 'detect_rate_pct': round(det_rate, 1),
        'false_alarm_rate_pct': round(fa_rate, 1),
        'tp': tp, 'fn': fn, 'fp': fp, 'tn': tn,
        'avg_boxes_per_frame': round(sum(box_counts) / len(box_counts), 2) if box_counts else 0,
        'video': 'vehicles.mp4', 'resolution': '1280x720',
        'time': time.strftime('%Y-%m-%d %H:%M:%S')
    }, f, ensure_ascii=False, indent=2)
    print('数据已存: verify_result.json')
