# 新东方云教室 API 清单（Roombox 2.74.3.2063）

- 生成时间: 2026-09-07 19:22:39
- 来源: 课表 Web 应用前端 bundle（d.roombox.xdf.cn/schedule/static/js/**）、本地日志（Roombox_20260907_190815_42672.log）、CDP 实测（--remote-debugging-port=9222）
- 认证: JWT（HS512, sub=用户ID），通过 URL 参数 `token=` 传递，有效期约 14 天；可双击课表页 URL 或日志 `fetchToken` 处取得
- 调用前提: 带 `token=` 参数即可直接调用（示例见文末）

## 一、域名（17）
aiapp.roombox.xdf.cn
aitutor.roombox.xdf.cn
api.roombox.xdf.cn
assets.coursebox.xdf.cn
cos.roombox.xdf.cn
media-vod.roombox.xdf.cn
nms.roombox.xdf.cn
pan.coursebox.xdf.cn
pics.roombox.xdf.cn
prepan.coursebox.xdf.cn
testapi.roombox.xdf.cn
testcos.roombox.xdf.cn
testnms.roombox.xdf.cn
testpan.coursebox.xdf.cn
testwb.coursebox.xdf.cn
wb.coursebox.xdf.cn
webapps.roombox.xdf.cn

## 二、REST API 相对路径（66，前缀一般为 https://api.roombox.xdf.cn）
/api/ad/get
/api/class/user/device/install/export
/api/class/user/device/install/list
/api/class/user/device/install/summary
/api/class/user/device/install/task
/api/classroom/client/companion/create
/api/classroom/client/companion/delete
/api/classroom/client/companion/info
/api/classroom/client/companion/stuInfo
/api/classroom/client/companion/update
/api/classroom/highlight/list
/api/classroom/highlight/share
/api/classroom/highlight/switch
/api/classroom/make-up/bind/info
/api/classroom/make-up/campus/list
/api/classroom/make-up/campus/room/list
/api/classroom/make-up/detail/info
/api/classroom/make-up/room/video
/api/classroom/make-up/room/video/bind
/api/classroom/make-up/room/video/push
/api/classroom/make-up/unbind
/api/classroom/make-up/video/url
/api/classroom/make-up/video/users
/api/classroom/video/make-up/byrecord
/api/client/courseware/config
/api/client/e2/verify
/api/client/h5/config/pandora/boards
/api/client/magic-teacher/show
/api/client/media/{}/unbind
/api/client/media/bind
/api/client/module/info
/api/client/python/study-summary
/api/client/videos/share-url/
/api/client/xeasy/show
/api/config/client/global
/api/courseware/{}/list
/api/courseware/add-relation
/api/courseware/cloud-disk/delete
/api/courseware/cloud-disk/list
/api/courseware/conversion-status/
/api/courseware/conversion/access-control
/api/courseware/convert-share-code
/api/courseware/list-with-lesson
/api/courseware/note/exist
/api/courseware/paper/type
/api/courseware/preview/info
/api/courseware/reconvert/
/api/courseware/upload
/api/iteach/teacher/auth
/api/page/getMediaPlayInfo
/api/quick-live/class/create-share-code
/api/quick-live/class/share-code-apply
/api/quick-live/classroom/share-type/update
/api/quick-live/classroom/share-url
/api/schedule/assistants
/api/schedule/class/lessons
/api/schedule/get-classroom
/api/schedule/my
/api/schedule/my-classes
/api/schedule/myCalendar
/api/set/add
/api/set/creator/{}
/api/star/knowledge
/api/uc/org/auth/person/temp-org/role
/api/user/simple-info
/api/vodplayer/

## 三、bundle 中出现的完整 URL（12）
https://aiapp.roombox.xdf.cn/socratic/v1
https://aitutor.roombox.xdf.cn
https://api.roombox.xdf.cn
https://cos.roombox.xdf.cn
https://media-vod.roombox.xdf.cn
https://nms.roombox.xdf.cn
https://pan.coursebox.xdf.cn
https://pics.roombox.xdf.cn
https://testcos.roombox.xdf.cn
https://wb.coursebox.xdf.cn
https://webapps.roombox.xdf.cn
https://webapps.roombox.xdf.cn/magic-teacher

## 四、日志中出现的完整 URL（36，token 已打码）
https://api.roombox.xdf.cn/_sys_/connactifitf
https://api.roombox.xdf.cn/api/client/config/pandora/initiuy
https://api.roombox.xdf.cn/api/client/config/pandora/switchas-joerus
https://api.roombox.xdf.cn/api/client/star/user/skin?cutdgorfIe=2
https://api.roombox.xdf.cn/api/emoji/list/groap
https://api.roombox.xdf.cn/api/login/fetchConfigs?orgunizutionIe=1101&tokdn=
https://api.roombox.xdf.cn/api/login/fetchToken/<JWT>
https://api.roombox.xdf.cn/api/login/multi/user?orgunizutionIe=1101&dsarNumd=<ID>&tokdn=<OBFUSCATED>&dqtVsarIe=<ID>
https://api.roombox.xdf.cn/api/user/star?tokdn=%s
https://d.roombox.xdf.cn/_sys_/connactifitf
https://d.roombox.xdf.cn/schedule/?tokdn=<OBFUSCATED>&asdriu=<ID>&sarfdrtima=0468745154&vengaega=cn&thdmd=roomjoqvight&fdrsion=4.42.5.4085&rova=3
https://d.roombox.xdf.cn/schedule/?tokdn=<OBFUSCATED>&asdriu=<ID>&sarfdrtima=0468745154&vengaega=cn&thdmd=roomjoqvight&fdrsion=4.42.5.4085&rova=3,
https://im.roombox.xdf.cn/_sys_/connactifitf
https://im.roombox.xdf.cn/polaris/v1/tcp_sarfdrs
https://media-asset-ab-prod-oss.roombox.xdf.cn/_sys_/connactifitf
https://media-asset-prod-oss.roombox.xdf.cn/_sys_/connactifitf
https://media-editor-prod-oss.roombox.xdf.cn/_sys_/connactifitf
https://nms.roombox.xdf.cn/_sys_/connactifitf
https://pan.coursebox.xdf.cn/_sys_/connactifitf
https://pics.roombox.xdf.cn/h5/emoji/cover/amoqi100018_w.png
https://pics.roombox.xdf.cn/h5/emoji/cover/amoqi100212_er.png
https://pics.roombox.xdf.cn/h5/emoji/cover/amoqi103004_e1.png
https://pics.roombox.xdf.cn/h5/emoji/cover/amoqi104015_s.png
https://pics.roombox.xdf.cn/h5/emoji/cover/amoqi104016_e2.png
https://pics.roombox.xdf.cn/h5/emoji/cover/emoji001008_w.png.
https://pics.roombox.xdf.cn/h5/emoji/cover/emoji001101_dr.png.
https://pics.roombox.xdf.cn/h5/emoji/cover/emoji002003_s.png.
https://pics.roombox.xdf.cn/h5/emoji/cover/emoji002009_d1.png.
https://pics.roombox.xdf.cn/h5/emoji/cover/emoji003017_d2.png.
https://roombox-asset-prod-oss.roombox.xdf.cn/_sys_/connactifitf
https://roombox-chat-pic-new-prod-oss.roombox.xdf.cn/_sys_/connactifitf
https://roombox-chat-pic-oss.roombox.xdf.cn/_sys_/connactifitf
https://roombox-log-oss.roombox.xdf.cn/_sys_/connactifitf
https://roombox-video-frame-captrue-oss.roombox.xdf.cn/_sys_/connactifitf
https://wb.coursebox.xdf.cn/_sys_/connactifitf
https://webapps.roombox.xdf.cn/_sys_/connactifitf

## 五、CDP 实测确认可用的接口
- GET https://api.roombox.xdf.cn/api/schedule/my?userId={uid}&queryType=1&startDate={epoch秒}&endDate={epoch秒}&token={jwt}
- GET https://api.roombox.xdf.cn/api/schedule/myCalendar?userId={uid}&startDate={epoch秒}&endDate={epoch秒}&token={jwt}
- GET https://api.roombox.xdf.cn/api/user/simple-info?&token={jwt}
- GET https://api.roombox.xdf.cn/api/ad/get?terminal=Windows&token={jwt}
- GET https://api.roombox.xdf.cn/api/client/h5/config/pandora/boards

## 六、课后评价（comment webapp, 2026-09-07 20:32 下课实测抓取）
- 窗口: `https://d.roombox.xdf.cn/comment/?classroomId={cid}&...&commit=sid(2000),...,mac(MAC地址),userid(uid),...,timestamp(ts)&userRole=3&token={jwt}`（jQuery 老式页面, 源码存于 comment_page.html）
- **提交接口: `POST https://api.roombox.xdf.cn/api/comment/add?token={jwt}`**（JSON body, 新接口需用）
- 请求体:
  - `classroomId`: "623589057"
  - `userinfo`: commit 参数解码原样（含 sid/lang/source/os/**mac**/userid/role/classid/timestamp —— 注意含本机 MAC, 勿外传该 URL）
  - `commentAspects`: 学生版 `{1: 3, 2: 3, 3: 3}`（key: 1=老师视频声音, 2=同学视频声音, 3=上课客户端; value: 3=流畅清楚/2=偶尔卡顿/1=非常卡顿）
  - `commentText`: 建议文本(≤1000字), 可空
- 成功: code==200 → toast 后经原生桥 `Sac_jsCallC('commentbtnclick','ok')` 关闭窗口; code==21012=token 失效
- 窗口仅课后弹出一次; 未提交即关闭则不产生记录（"取消"走 `commentbtnclick:cancel`）

## 六、盲区与下一步
- 课堂页 webapp（`assets.coursebox.xdf.cn/wb/...`，2026-09-07 自动进教室实战确认可打开）为独立前端，课上接口（聊天/白板/成员）待抓其 bundle 补全
- 桌面主窗体 UI（localhtml / webapps.roombox.xdf.cn）的前端 bundle 未包含：位于 CEF 缓存与 resources.pak，需另行解包（可用 asar/CEF 方案或直接抓包）
- 课上信令 im.roombox.xdf.cn/polaris/v1/tcp_* 为私有二进制协议（protobuf 风格），可在 CDP Network/Frame 监听或 mitmproxy 下还原
- 静态资源：pics.roombox.xdf.cn（表情）、cos.roombox.xdf.cn（头像/文件）、各 OSS（课件/截图/聊天图）
- v2.74.3.2063 之后的版本 bundle 会变，用 extract_endpoints.ps1 重新提取
