# 课上接口清单（课堂/白板 Web 应用 + 实时快照）

- 抓取时间: 2026-09-07 19:43:31
- 课堂: teacherClassId=623589057 cid=623589060 (27考研专业课一对一, uid=25527722)
- 来源:
  - 课堂页实时 XHR 快照（直播 Web 应用: assets.coursebox.xdf.cn/wb/<hash>/）
  - bundle 提取: js_wb/(白板主应用), js_wbtools/(点名/抢答/签到等互动工具), js_sdk/(wbSdk, im.sdk)
- 认证: 与主应用同为 JWT(token=), 另有课堂上下文参数 (cid/teacherClassId/identity=3 学生)

## 一、实时 XHR 快照（课上实际请求, token 已打码）
https://api.roombox.xdf.cn/api/client/h5/config/pandora/boards
https://api.roombox.xdf.cn/api/client/h5/config/pandora/boards?_mode=dev
https://api.roombox.xdf.cn/api/emoji/list?cid=623589060&uid=25527722&_mode=dev
https://api.roombox.xdf.cn/api/matrix/client/classroom/sign-in/student/info?cid=623589057&classroomId=623589057&_mode=dev
https://api.roombox.xdf.cn/quiz/api/v1/quiz/latest/unSubmit?_mode=dev
https://api.roombox.xdf.cn/quiz/api/vote/user/info?_mode=dev
https://highschool-exercise.roombox.xdf.cn/_sys_/connectivity
https://im.roombox.xdf.cn/polaris/v1/ws_servers
https://webapps.roombox.xdf.cn/wbtools/asset-manifest.json?t=1788780932020
https://webapps.roombox.xdf.cn/wbtools/index.html?t=1788780932022
https://webapps.roombox.xdf.cn/wbtools/index.html?t=1788780934223
https://webapps.roombox.xdf.cn/wbtools/static/css/168.28a7f2a4.chunk.css
https://webapps.roombox.xdf.cn/wbtools/static/css/201.4072a86d.chunk.css
https://webapps.roombox.xdf.cn/wbtools/static/css/267.0e0eb31d.chunk.css
https://webapps.roombox.xdf.cn/wbtools/static/css/330.064f059d.chunk.css
https://webapps.roombox.xdf.cn/wbtools/static/css/478.e1d160fe.chunk.css
https://webapps.roombox.xdf.cn/wbtools/static/css/56.70a56609.chunk.css
https://webapps.roombox.xdf.cn/wbtools/static/css/691.c5859543.chunk.css
https://webapps.roombox.xdf.cn/wbtools/static/css/744.c99d00d8.chunk.css
https://webapps.roombox.xdf.cn/wbtools/static/css/97.4a05a7f7.chunk.css
https://webapps.roombox.xdf.cn/wbtools/static/css/main.ae22add9.css
https://webapps.roombox.xdf.cn/wbtools/static/js/168.fe0ff92e.chunk.js
https://webapps.roombox.xdf.cn/wbtools/static/js/171.2698f941.chunk.js
https://webapps.roombox.xdf.cn/wbtools/static/js/201.762e1b86.chunk.js
https://webapps.roombox.xdf.cn/wbtools/static/js/267.a634f7f0.chunk.js
https://webapps.roombox.xdf.cn/wbtools/static/js/302.9cef3ba4.chunk.js
https://webapps.roombox.xdf.cn/wbtools/static/js/330.ac14471f.chunk.js
https://webapps.roombox.xdf.cn/wbtools/static/js/458.68e7450b.chunk.js
https://webapps.roombox.xdf.cn/wbtools/static/js/478.28a608b8.chunk.js
https://webapps.roombox.xdf.cn/wbtools/static/js/56.12b66fdb.chunk.js
https://webapps.roombox.xdf.cn/wbtools/static/js/591.f6c7a70b.chunk.js
https://webapps.roombox.xdf.cn/wbtools/static/js/632.0bb0db01.chunk.js
https://webapps.roombox.xdf.cn/wbtools/static/js/691.acd6bd0d.chunk.js
https://webapps.roombox.xdf.cn/wbtools/static/js/744.672925f2.chunk.js
https://webapps.roombox.xdf.cn/wbtools/static/js/808.0162c268.chunk.js
https://webapps.roombox.xdf.cn/wbtools/static/js/97.49afde44.chunk.js
https://webapps.roombox.xdf.cn/wbtools/static/js/main.f6141dbe.js
https://webapps.roombox.xdf.cn/wbtools/static/media/animation.0caa2f9e.svga
https://webapps.roombox.xdf.cn/wbtools/static/media/beam.048c08ec60b6f5784f82.png
https://webapps.roombox.xdf.cn/wbtools/static/media/bg_content.fc0ff86cc888fe6bc106.png
https://webapps.roombox.xdf.cn/wbtools/static/media/bg_signin_big.0bd798b6fa951249ad11.png
https://webapps.roombox.xdf.cn/wbtools/static/media/bg_signin_small.c70d6cbabb838cde7e12.png
https://webapps.roombox.xdf.cn/wbtools/static/media/bg_wheel.1857849ceb8012ea4b88.png
https://webapps.roombox.xdf.cn/wbtools/static/media/bg.5637288f651727076719.png
https://webapps.roombox.xdf.cn/wbtools/static/media/btn_other_play_2x@2x.4fd12f716672aa6bc881.png
https://webapps.roombox.xdf.cn/wbtools/static/media/btn_other_reset_2x@2x.524da32756565afe64a9.png
https://webapps.roombox.xdf.cn/wbtools/static/media/btn_other_suspend_2x@2x.7358a3048a8060c8984b.png
https://webapps.roombox.xdf.cn/wbtools/static/media/btn_random_click@2x.9531cb368757b46d3545.png
https://webapps.roombox.xdf.cn/wbtools/static/media/btn_random_invite_click-en@2x.67b5d85c9a52ee65a9e1.png
https://webapps.roombox.xdf.cn/wbtools/static/media/btn_random_invite_click@2x.4e1bcf49864c68bb0172.png
https://webapps.roombox.xdf.cn/wbtools/static/media/btn_random_invite_normal-en@2x.6d55a93b2926668390c4.png
https://webapps.roombox.xdf.cn/wbtools/static/media/btn_random_invite_normal@2x.eabca7ee642d420664be.png
https://webapps.roombox.xdf.cn/wbtools/static/media/btn_random_restart_normal@2x.1771d4ecbe3e42ac2d2b.png
https://webapps.roombox.xdf.cn/wbtools/static/media/btn_random_start_click-en@2x.e86139bef0b29106e767.png
https://webapps.roombox.xdf.cn/wbtools/static/media/dice.df279edbd977e3796683.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_0.78fe82f16261cae35cef.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_1.b32f2cdd751fc0bf35cd.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_13.731f29ca0ed4ecdbe055.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_14.fca345b46321f97a1632.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_15.7369ca5d6867357a426f.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_16.1af669e4847c3e9d9da0.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_17.19c77dd6141d5f8a8240.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_2.8ac22eab4d5931357876.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_23.0e4e460cdc56276bdf54.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_24.e278547d057c8f9ddef2.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_3.2e586a31c15791076af3.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_34.fcb088c5f8d0fe9d7f7d.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_4.eb9832e5c9be43bf6cf6.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_5.0f84904a366fb406cdbd.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_bg_public-popup@2x.03197c8408fa20183368.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_random_board-bg1-en@2x.1a6b1204d36c6bc231b3.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_random_board-bg1@2x.d36a8b89d29f2ff8e427.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_random_board-bg2-en@2x.2548e4f5d9a35c0815e9.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_random_board-bg2@2x.c29efab9fedbc94b3f4b.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_random_card-back@2x.81a5fbe82ade4ee8c48e.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_random_selected-bg@2x.b48d4e15f1b97285e953.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_random_title@2x.3e2a303f4383d168ce12.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_random_wood-1@2x.1c3d697c10a3fc4b1d96.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_random_wood-2@2x.20b84b95d3ab650a148e.png
https://webapps.roombox.xdf.cn/wbtools/static/media/img_scene_empty.7c43c9ef5e88270d475b.png
https://webapps.roombox.xdf.cn/wbtools/static/media/list_empty.b513f35c295d929ed192.png
https://webapps.roombox.xdf.cn/wbtools/static/media/normal_open.fabcfd58fee0d16c2168.png
https://webapps.roombox.xdf.cn/wbtools/static/media/pointer.f1654ae664fce74bec36.png
https://webapps.roombox.xdf.cn/wbtools/static/media/rb_team_img_student_defult0@2x.a01f0246a45adcd9146a.png
https://webapps.roombox.xdf.cn/wbtools/static/media/responder_lights01@2x.867e380f59814d691ebc.png
https://webapps.roombox.xdf.cn/wbtools/static/media/responder_lights02@2x.a5eb0de1b983f479757f.png
https://webapps.roombox.xdf.cn/wbtools/static/media/responder_lights03@2x.36ae8a6b6ebc9a57e627.png
https://webapps.roombox.xdf.cn/wbtools/static/media/responder_main@2x.1f671f3116ae6290c40e.png
https://webapps.roombox.xdf.cn/wbtools/static/media/responder_shine@2x.0d49acd4c6d739d0c8ea.png
https://webapps.roombox.xdf.cn/wbtools/static/media/responder_shine02@2x.e97c96030e9a458d9c42.png
https://webapps.roombox.xdf.cn/wbtools/static/media/responder_text-bg_green@2x.c45f3b5e99adce5fc775.png
https://webapps.roombox.xdf.cn/wbtools/static/media/responder_text-bg_red@2x.57d2215569d8c747b294.png
https://webapps.roombox.xdf.cn/wbtools/static/media/responder_title@2x.fdc13ef6dfaed8b5fbd7.png
https://webapps.roombox.xdf.cn/wbtools/static/media/signin_icon_01.92f4f06fd958e3fd959f.png
https://webapps.roombox.xdf.cn/wbtools/static/media/signin_icon_02.3c0d0e0b70ac387a520c.png
https://webapps.roombox.xdf.cn/wbtools/static/media/states_red%20packet%20student_fail%20top%20bg.cc1b3356137e7f2580ce.png
https://webapps.roombox.xdf.cn/wbtools/static/media/student_result.677452abb4532936ade0.png

## 二、bundle 提取的接口路径
/api/blackboard/confirm
/api/blackboard/file
/api/blackboard/QRcode
/api/client/classroom/student/add
/api/client/classroom/student/query-add-phone
/api/client/config/by-token
/api/client/config/classroom/operation-position
/api/client/external-link/wrapper
/api/client/h5/config/pandora/boards
/api/client/magic-teacher/show
/api/client/module/info
/api/courseware/info
/api/courseware/reconvert/
/api/courseware/v2/
/api/emoji/list
/api/inode/
/api/magic-teacher/ack
/api/magic-teacher/latest
/api/magic-teacher/status
/api/matrix/client/classroom/sign-in/end
/api/matrix/client/classroom/sign-in/info
/api/matrix/client/classroom/sign-in/start
/api/matrix/client/classroom/sign-in/student
/api/matrix/client/classroom/sign-in/student/info
/api/matrix/client/classroom/sign-in/student/list
/api/matrix/client/classroom/sign-in/sub/list
/api/quiz-attendance/school-whitelist-config
/api/quiz-attendance/status
/api/quiz-attendance/sync
/api/quiz-machine/sign
/api/quiz-machine/sign/list
/api/quiz-machine/sign/type
/api/upload/oss/signed-url
/api/user/teacher-audit
/api/v1/quiz/ack
/api/v1/quiz/current
/api/v1/quiz/latest/unSubmit
/api/v1/quiz/querySubmitCid
/api/v1/quiz/statistics
/api/v1/quiz/submit
/api/v1/quiz/submit/offline
/api/v1/quiz/submit/statistics
/api/v1/quiz/unSubmit/statistics
/api/v1/teacher/exam
/api/vote/ack
/api/vote/data/item
/api/vote/data/overview
/api/vote/statistic/subclassroom
/api/vote/submit
/api/vote/user/info
/api/wb/tool/preference/config
/api/xeasy/offline/submit
/api/xeasy/sub-classroom/list
/classroom/operation-position
/classroom/sign-in/end
/classroom/sign-in/info
/classroom/sign-in/start
/classroom/sign-in/student
/classroom/sign-in/student/info
/classroom/sign-in/student/list
/classroom/sign-in/sub/list
/classroom/student/add
/classroom/student/query-add-phone
/matrix/client/classroom/sign-in/end
/matrix/client/classroom/sign-in/info
/matrix/client/classroom/sign-in/start
/matrix/client/classroom/sign-in/student
/matrix/client/classroom/sign-in/student/info
/matrix/client/classroom/sign-in/student/list
/matrix/client/classroom/sign-in/sub/list
/polaris/v1/ws_servers
/quiz/api/magic-teacher/ack
/quiz/api/magic-teacher/latest
/quiz/api/magic-teacher/status
/quiz/api/quiz-machine/sign
/quiz/api/quiz-machine/sign/list
/quiz/api/quiz-machine/sign/type
/quiz/api/v1/quiz/ack
/quiz/api/v1/quiz/current
/quiz/api/v1/quiz/latest/unSubmit
/quiz/api/v1/quiz/querySubmitCid
/quiz/api/v1/quiz/statistics
/quiz/api/v1/quiz/submit
/quiz/api/v1/quiz/submit/offline
/quiz/api/v1/quiz/submit/statistics
/quiz/api/v1/quiz/unSubmit/statistics
/quiz/api/v1/teacher/exam
/quiz/api/vote/ack
/quiz/api/vote/data/item
/quiz/api/vote/data/overview
/quiz/api/vote/statistic/subclassroom
/quiz/api/vote/submit
/quiz/api/vote/user/info
/quiz/api/xeasy/offline/submit
ws://127.0.0.1:
ws://127.0.0.1:9002

## 三、WebSocket / 信令
- 发现入口: https://im.roombox.xdf.cn/polaris/v1/ws_servers
  - 实测: ❌ 404 (err_code 600104「页面未找到」) —— 该端点需要 SDK 层附加的鉴权/签名头; 页面 SDK 同样收到 404 后回退默认服务器
- **真实连接地址（2026-09-07 20:20 课堂中实测捕获）: `wss://im-tx-sh8.roombox.xdf.cn/ws`** （腾讯云上海节点, 备用域 im.yclassroom.com）
  - 捕获工具: `ws_capture.ps1`（-Mode Now 反查已建立连接 / -Mode Watch 订阅 Network 事件）
- 帧格式观察: 二进制帧(opcode=2), protobuf 封装: 帧前缀 `ce 01` + 长度/序列字段, 之后为 protobuf 消息（可见 `72 xx` = field 14, `28 xx` = field 5 等 wire 字段）; 30 秒观察窗内 4 帧(2发2收, ~30-180B), 呈心跳/状态同步节奏
- 模板: 无（bundle 内无 wss:// 字面量, 连接地址运行时拼接）

## 四、域名
- 课堂 bundle 内出现的域均为 yclassroom.com 生产镜像（运行时按映射换回 roombox.xdf.cn）: 
	api.yclassroom.com
im.yclassroom.com
testapi.yclassroom.com
testim.yclassroom.com

## 五、说明
- 路径模板中 `{}` 为占位符（源码里的模板变量）
- 快照内含 `_mode=dev` 等源生参数, 属应用自身行为, 照常携带即可
- 互动工具(wbtools)为独立子应用: 随机点名/抢答/红包/签到(sign-in)等
