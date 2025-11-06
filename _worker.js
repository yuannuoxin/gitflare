// Durable Object 类定义（必须导出）
export class ChatRoom {
    constructor(state, env) {
        this.state = state;
        this.storage = state.storage;
    }

    async fetch(request) {
        const url = new URL(request.url);
        if (url.pathname === '/chat/history') {
            const history = await this.storage.list({ limit: 10 });
            const messages = [];
            for (const key of history.keys) {
                const msg = await this.storage.get(key.name);
                messages.push(msg);
            }
            return new Response(JSON.stringify(messages, null, 2), {
                headers: { 'Content-Type': 'application/json' },
            });
        }

        if (request.method === 'POST') {
            const body = await request.text();
            const id = Date.now().toString();
            await this.storage.put(id, body);
            await this.env.EVENTS.send({ type: 'message', room: this.state.id, content: body });
            return new Response('Message saved', { status: 201 });
        }

        return new Response('ChatRoom DO ready', { status: 200 });
    }
}

// 主 Worker 入口
export default {
    async fetch(request, env, ctx) {
        const url = new URL(request.url);

        // 1. 读取环境变量
        const uuid = env.UUID || 'not-set';
        const apiKey = env.API_KEY || 'missing';

        // 2. KV 示例：写入并读取会话
        if (url.pathname === '/kv') {
            await env.SESSIONS.put(`user:${uuid}`, JSON.stringify({ lastSeen: new Date().toISOString(), apiKey }));
            const data = await env.SESSIONS.get(`user:${uuid}`, 'json');
            return new Response(JSON.stringify(data, null, 2), {
                headers: { 'Content-Type': 'application/json' },
            });
        }

        // 3. R2 示例：列出文件 or 上传
        if (url.pathname === '/r2/list') {
            const objects = await env.ASSETS.list();
            return new Response(JSON.stringify(objects, null, 2), {
                headers: { 'Content-Type': 'application/json' },
            });
        }

        if (url.pathname === '/r2/upload' && request.method === 'POST') {
            const key = `uploads/${Date.now()}.txt`;
            await env.ASSETS.put(key, request.body);
            return new Response(`Uploaded to ${key}`, { status: 201 });
        }

        // 4. D1 示例：查询用户表
        if (url.pathname === '/d1/users') {
            try {
                // 假设有一个 users 表：CREATE TABLE users (id TEXT, name TEXT, created_at INTEGER);
                const { results } = await env.USERS.prepare('SELECT * FROM users LIMIT 5').all();
                return new Response(JSON.stringify(results, null, 2), {
                    headers: { 'Content-Type': 'application/json' },
                });
            } catch (e) {
                return new Response('D1 error: ' + e.message, { status: 500 });
            }
        }

        // 5. Durable Object 示例：获取聊天室实例
        if (url.pathname.startsWith('/do/chat/')) {
            const roomId = url.pathname.split('/')[3] || 'default';
            const id = env.CHAT_ROOM.idFromName(roomId);
            const stub = env.CHAT_ROOM.get(id);
            return stub.fetch(new Request(`https://fake-host/chat${url.pathname.replace(/\/do/, '')}`, request));
        }

        // 6. Queue 示例：发送事件
        if (url.pathname === '/queue/send') {
            await env.EVENTS.send({
                timestamp: Date.now(),
                event: 'test',
                user: uuid,
                message: 'Hello from Worker!',
            });
            return new Response('Event sent to queue', { status: 202 });
        }

        // 主页说明
        return new Response(`
      🧪 GitFlare Full Bindings Demo

      Endpoints:
        GET  /kv             → Use KV (SESSIONS)
        GET  /r2/list        → List R2 objects
        POST /r2/upload     → Upload to R2
        GET  /d1/users       → Query D1
        POST /do/chat/room1 → Send message to Durable Object "room1"
        GET  /do/chat/room1/history → Get chat history
        GET  /queue/send     → Send event to Queue

      Env:
        UUID = ${uuid}
        API_KEY = ${apiKey ? '***' : 'missing'}

      All bindings are active!
    `, {
            headers: { 'Content-Type': 'text/plain; charset=utf-8' }
        });
    },
};