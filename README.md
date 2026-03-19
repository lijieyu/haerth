# haerth

`haerth.cn` 的独立静态站点仓库。

## 文件

- `index.html`: 首页
- `styles.css`: 样式
- `nginx.haerth.conf`: 站点 Nginx 配置
- `deploy.sh`: 同步站点文件并更新服务器 Nginx 配置

## 部署

```bash
./deploy.sh
```

默认发布到同一台 ECS：

- 静态文件目录：`/var/www/haerth-web`
- Nginx 配置：`/etc/nginx/sites-available/haerth`

说明：

- 当前 `haerth.cn` 的公网 DNS 没有 `A` 记录，部署完成后仍需要在域名控制台补解析到 ECS IP。
- 补好 DNS 后，HTTP 会直接命中当前站点配置。
