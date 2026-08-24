#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build local_dict.json for Pointrans.

Sources:
  - CC-CEDICT (https://www.mdbg.net/chinese/dictionary?page=cc-cedict),
    community-maintained Chinese-English dictionary, CC BY-SA 4.0.
  - Curated programming / settings / AI-reasoning vocabulary defined at the
    bottom of this file (PROG_DICT), CC0 / project-authored.

Usage:
  python3 scripts/gen_dict.py

Downloads the latest CC-CEDICT, merges it with the existing
Sources/Pointrans/local_dict.json (preserving hand-curated entries), overlays
the curated programming vocabulary, and writes the result back to the same file.

Note on licensing: CC-CEDICT is CC BY-SA. Fine for personal use; a commercial
closed-source release should either avoid distributing it or switch to a
commercially-licensed lexicon.
"""
import json
import re
import collections
import os
import sys
import gzip
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DICT_PATH = os.path.join(ROOT, 'Sources', 'Pointrans', 'local_dict.json')
CEDICT_URL = 'https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz'

STOP = set("""the of to and a in for on with is are be as at or from by an that this it not have but which we you he she they them all will would can could should may might do does did was were been its has had having one two three four five six seven eight nine ten am been being also there their then than when""".split())

def fetch_cedict() -> str:
    print(f'Downloading CC-CEDICT from {CEDICT_URL} ...')
    try:
        with urllib.request.urlopen(CEDICT_URL, timeout=120) as r:
            gz = r.read()
    except Exception as e:
        print(f'Failed to download CC-CEDICT: {e}', file=sys.stderr)
        sys.exit(1)
    text = gzip.decompress(gz).decode('utf-8')
    print(f'CEDICT: {len(text) / 1e6:.1f} MB downloaded')
    return text

def clean_gloss(g):
    g = re.sub(r'^(CL:|surname |variant of |old variant of |nonstandard variant of |archaic variant of |abbr\.? for |see also |same as |classifier for |measure word for |fig\.?)', '', g)
    return g.strip(' .,;:()[]')

def en_tokens(g):
    return re.findall(r"[a-zA-Z][a-zA-Z'-]*", clean_gloss(g))

def parse_cedict(text):
    entries = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        m = re.match(r'^(\S+) (\S+) \[[^\]]+\] (/.+)$', line)
        if not m:
            continue
        trad, simp, gloss_part = m.group(1), m.group(2), m.group(3)
        glosses = [g for g in gloss_part.strip('/').split('/') if g]
        if simp and glosses:
            entries.append((trad, simp, glosses))
    return entries

def load_seed():
    if os.path.exists(DICT_PATH):
        with open(DICT_PATH, encoding='utf-8') as f:
            d = json.load(f)
        return d.get('en_to_zh', {}), d.get('zh_to_en', {})
    return {}, {}

def main():
    entries = parse_cedict(fetch_cedict())
    print(f'CEDICT entries: {len(entries)}')
    seed_en, seed_zh = load_seed()
    print(f'Seed: {len(seed_en)} en, {len(seed_zh)} zh')

    # English token frequency across glosses (used to pick better Chinese glosses)
    en_freq = collections.Counter()
    for _, _, glosses in entries:
        seen = set()
        for g in glosses:
            for tok in en_tokens(g):
                tl = tok.lower()
                if tl not in STOP and 2 <= len(tl) <= 24 and tl not in seen:
                    en_freq[tl] += 1
                    seen.add(tl)

    # ---- en_to_zh: reverse index, every English word seen in any gloss ----
    en_cands = collections.defaultdict(list)
    for _, simp, glosses in entries:
        for g in glosses:
            for tok in set(t.lower() for t in en_tokens(g)):
                if tok in STOP or not (2 <= len(tok) <= 24):
                    continue
                en_cands[tok].append(simp)

    en_to_zh = {}
    for word in en_cands:
        cands = en_cands[word]
        ccount = collections.Counter(cands)
        top = [c for c, _ in ccount.most_common(4)]
        zh = ' / '.join(top[:3])
        if len(zh) > 90:
            zh = top[0]
        en_to_zh[word] = zh
    print(f'en_to_zh from CEDICT reverse: {len(en_to_zh)}')

    # ---- zh_to_en: every Chinese entry ----
    zh_cands = collections.defaultdict(list)
    for _, simp, glosses in entries:
        score = 0
        toks = []
        for g in glosses:
            for tok in en_tokens(g):
                tl = tok.lower()
                if tl not in STOP and len(tl) >= 2:
                    score += en_freq[tl]
                    toks.append(tok)
        if toks:
            zh_cands[simp].append((score, toks))

    zh_to_en = {}
    for simp, infos in zh_cands.items():
        infos.sort(key=lambda x: -x[0])
        seen = set()
        glosses = []
        for t in infos[0][1]:
            key = t.lower()
            if key not in seen:
                seen.add(key)
                glosses.append(t)
        top = glosses[:4] if len(glosses) <= 6 else glosses[:2]
        zh_to_en[simp] = ' / '.join(top)
    print(f'zh_to_en from CEDICT: {len(zh_to_en)}')

    # ---- merge: seed first, CEDICT fills gaps, programming overrides ----
    prog_en, prog_zh = PROG_DICT
    merged_en = {}
    merged_en.update(seed_en)
    for k, v in en_to_zh.items():
        merged_en.setdefault(k, v)
    merged_en.update(prog_en)

    merged_zh = {}
    merged_zh.update(seed_zh)
    for k, v in zh_to_en.items():
        merged_zh.setdefault(k, v)
    merged_zh.update(prog_zh)

    out = {'en_to_zh': dict(sorted(merged_en.items())), 'zh_to_en': dict(sorted(merged_zh.items()))}
    with open(DICT_PATH, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write('\n')
    size = os.path.getsize(DICT_PATH)
    print(f'FINAL: en_to_zh={len(out["en_to_zh"])}, zh_to_en={len(out["zh_to_en"])}, size={size/1024/1024:.2f}MB')

# ============================================================
# Curated programming / settings / AI vocabulary.
# Abbreviations, phrases and words, keyed lowercase for en_to_zh.
# ============================================================
PROG_EN = {}

# ---- abbreviations ----
PROG_EN.update({
    'api': '应用程序接口 / API', 'sdk': '软件开发工具包', 'ide': '集成开发环境',
    'cli': '命令行界面', 'gui': '图形用户界面', 'ui': '用户界面', 'ux': '用户体验',
    'db': '数据库', 'dbms': '数据库管理系统', 'sql': 'SQL 结构化查询语言',
    'nosql': '非关系型数据库', 'crud': '增删改查', 'mvc': '模型-视图-控制器',
    'mvvm': '模型-视图-视图模型', 'mvp': '最小可行产品', 'oop': '面向对象编程',
    'fp': '函数式编程', 'http': '超文本传输协议', 'https': '安全超文本传输协议',
    'ftp': '文件传输协议', 'sftp': '安全文件传输协议', 'ssh': '安全外壳协议',
    'tcp': '传输控制协议', 'udp': '用户数据报协议', 'ip': '互联网协议',
    'dns': '域名系统', 'dhcp': '动态主机配置协议', 'tls': '传输层安全协议',
    'ssl': '安全套接层协议', 'json': 'JSON 数据格式', 'xml': 'XML 可扩展标记语言',
    'html': 'HTML 超文本标记语言', 'css': 'CSS 层叠样式表', 'js': 'JavaScript',
    'ts': 'TypeScript', 'cpu': '中央处理器', 'gpu': '图形处理器', 'ram': '随机存取存储器',
    'rom': '只读存储器', 'ssd': '固态硬盘', 'hdd': '机械硬盘', 'os': '操作系统',
    'vm': '虚拟机', 'ci': '持续集成', 'cd': '持续交付/部署', 'cors': '跨域资源共享',
    'jwt': 'JSON Web 令牌', 'oauth': 'OAuth 开放授权', 'rest': 'REST 表述性状态转移',
    'rpc': '远程过程调用', 'ipc': '进程间通信', 'abi': '应用二进制接口',
    'bfs': '广度优先搜索', 'dfs': '深度优先搜索', 'dp': '动态规划',
    'tdd': '测试驱动开发', 'bdd': '行为驱动开发', 'ddd': '领域驱动设计',
    'etl': '抽取-转换-加载', 'elt': '抽取-加载-转换', 'saas': '软件即服务',
    'iaas': '基础设施即服务', 'paas': '平台即服务', 'k8s': 'Kubernetes 容器编排',
    'llm': '大语言模型', 'ai': '人工智能', 'ml': '机器学习', 'dl': '深度学习',
    'nlp': '自然语言处理', 'gpt': '生成式预训练模型', 'orm': '对象关系映射',
    'lms': '学习管理系统', 'ios': '苹果移动操作系统', 'android': '安卓操作系统',
    'sqlite': 'SQLite 嵌入式数据库', 'regex': '正则表达式', 'regexp': '正则表达式',
    'vim': 'Vim 编辑器', 'url': '统一资源定位符', 'uri': '统一资源标识符',
    'uuid': '通用唯一标识符', 'id': '标识符', 'pdf': '便携式文档格式',
    'svg': '可缩放矢量图形', 'png': 'PNG 图片格式', 'jpg': 'JPEG 图片格式',
    'gif': 'GIF 动图格式', 'yaml': 'YAML 数据格式', 'toml': 'TOML 数据格式',
    'npm': 'npm 包管理器', 'pip': 'pip 包管理器', 'brew': 'Homebrew 包管理器',
    'git': 'Git 版本控制', 'svn': 'SVN 版本控制', 'hg': 'Mercurial 版本控制',
    'vscode': 'Visual Studio Code 编辑器', 'xcode': 'Xcode 开发环境',
    'linux': 'Linux 操作系统', 'macos': 'macOS 操作系统', 'windows': 'Windows 操作系统',
    'unix': 'Unix 操作系统', 'docker': 'Docker 容器', 'k8s': 'Kubernetes 编排',
    'aws': '亚马逊云服务', 'azure': '微软云服务', 'gcp': '谷歌云平台',
    'ipv4': 'IPv4 地址', 'ipv6': 'IPv6 地址', 'mac': '媒体访问控制地址',
})

# ---- phrases ----
PROG_EN.update({
    'open source': '开源的 / 开放源代码', 'machine learning': '机器学习',
    'artificial intelligence': '人工智能', 'natural language processing': '自然语言处理',
    'deep learning': '深度学习', 'neural network': '神经网络',
    'large language model': '大语言模型', 'user interface': '用户界面',
    'command line': '命令行', 'command line interface': '命令行界面',
    'pull request': '拉取请求', 'merge request': '合并请求', 'code review': '代码审查',
    'unit test': '单元测试', 'integration test': '集成测试', 'end to end test': '端到端测试',
    'version control': '版本控制', 'version control system': '版本控制系统',
    'source code': '源代码', 'compile error': '编译错误', 'runtime error': '运行时错误',
    'stack overflow': '栈溢出', 'heap overflow': '堆溢出', 'buffer overflow': '缓冲区溢出',
    'garbage collection': '垃圾回收', 'design pattern': '设计模式', 'data structure': '数据结构',
    'linked list': '链表', 'hash table': '哈希表', 'binary tree': '二叉树',
    'binary search': '二分查找', 'linear search': '线性查找',
    'breadth first search': '广度优先搜索', 'depth first search': '深度优先搜索',
    'divide and conquer': '分治法', 'dynamic programming': '动态规划',
    'time complexity': '时间复杂度', 'space complexity': '空间复杂度',
    'big o notation': '大 O 记法', 'high level language': '高级语言',
    'low level language': '低级语言', 'object oriented programming': '面向对象编程',
    'functional programming': '函数式编程', 'type safety': '类型安全',
    'null safety': '空安全', 'error handling': '错误处理', 'exception handling': '异常处理',
    'input output': '输入输出', 'read only': '只读', 'continuous integration': '持续集成',
    'continuous delivery': '持续交付', 'continuous deployment': '持续部署',
    'micro service': '微服务', 'message queue': '消息队列', 'load balancer': '负载均衡器',
    'virtual machine': '虚拟机', 'relational database': '关系数据库',
    'non relational database': '非关系数据库', 'key value store': '键值存储',
    'data warehouse': '数据仓库', 'data lake': '数据湖', 'big data': '大数据',
    'real time': '实时的', 'distributed system': '分布式系统', 'fault tolerance': '容错',
    'high availability': '高可用性', 'software as a service': '软件即服务',
    'platform as a service': '平台即服务', 'infrastructure as a service': '基础设施即服务',
    'operating system': '操作系统', 'database management system': '数据库管理系统',
    'application programming interface': '应用程序接口', 'artificial neural network': '人工神经网络',
    'recommendation system': '推荐系统', 'search engine': '搜索引擎',
    'back end': '后端', 'front end': '前端', 'full stack': '全栈',
    'web application': '网页应用', 'mobile application': '移动应用',
    'cloud computing': '云计算', 'edge computing': '边缘计算',
    'internet of things': '物联网', 'virtual reality': '虚拟现实',
    'augmented reality': '增强现实', 'block chain': '区块链',
    'cyber security': '网络安全', 'data mining': '数据挖掘',
    'data analysis': '数据分析', 'data visualization': '数据可视化',
    'network protocol': '网络协议', 'transport layer': '传输层',
    'application layer': '应用层', 'session layer': '会话层',
    'presentation layer': '表示层', 'network layer': '网络层',
    'data link layer': '数据链路层', 'physical layer': '物理层',
    'domain name': '域名', 'domain name system': '域名系统',
    'access control': '访问控制', 'user authentication': '用户认证',
    'two factor authentication': '双因素认证', 'single sign on': '单点登录',
    'encryption key': '加密密钥', 'public key': '公钥', 'private key': '私钥',
    'digital signature': '数字签名', 'hash function': '哈希函数',
    'memory management': '内存管理', 'process management': '进程管理',
    'thread pool': '线程池', 'event loop': '事件循环', 'asynchronous programming': '异步编程',
    'reactive programming': '响应式编程', 'declarative programming': '声明式编程',
    'imperative programming': '命令式编程', 'test driven development': '测试驱动开发',
    'behavior driven development': '行为驱动开发', 'agile development': '敏捷开发',
    'scrum': 'Scrum 敏捷框架', 'kanban': '看板方法', 'code smell': '代码异味',
    'technical debt': '技术债', 'legacy code': '遗留代码', 'spaghetti code': '意大利面条式代码',
    'god object': '上帝对象', 'memory leak': '内存泄漏', 'race condition': '竞态条件',
    'segmentation fault': '段错误', 'integer overflow': '整数溢出', 'undefined behavior': '未定义行为',
    'null pointer': '空指针', 'dangling pointer': '悬空指针', 'smart pointer': '智能指针',
    'reference counting': '引用计数', 'copy on write': '写时复制',
    'dependency injection': '依赖注入', 'inversion of control': '控制反转',
    'service locator': '服务定位器', 'factory pattern': '工厂模式',
    'singleton pattern': '单例模式', 'observer pattern': '观察者模式',
    'strategy pattern': '策略模式', 'adapter pattern': '适配器模式',
    'decorator pattern': '装饰器模式', 'proxy pattern': '代理模式',
    'iterator pattern': '迭代器模式', 'state machine': '状态机',
    'finite state machine': '有限状态机', 'regular expression': '正则表达式',
    'lambda expression': 'Lambda 表达式', 'anonymous function': '匿名函数',
    'higher order function': '高阶函数', 'pure function': '纯函数',
    'side effect': '副作用', 'first class function': '一等函数',
    'type inference': '类型推断', 'type casting': '类型转换', 'type annotation': '类型标注',
    'type erasure': '类型擦除', 'generic type': '泛型类型', 'optional chaining': '可选链',
    'nil coalescing': '空值合并', 'default argument': '默认参数',
    'variable argument': '可变参数', 'named parameter': '命名参数',
    'trailing closure': '尾随闭包', 'capture list': '捕获列表',
    'automatic reference counting': '自动引用计数', 'grand central dispatch': 'Grand Central Dispatch',
    'thread safety': '线程安全', 'data race': '数据竞争', 'atomic operation': '原子操作',
    'dead lock': '死锁', 'livelock': '活锁', 'semaphore': '信号量',
    'condition variable': '条件变量', 'critical section': '临界区',
    'mutual exclusion': '互斥', 'spin lock': '自旋锁', 'read write lock': '读写锁',
})

# ---- single words ----
PROG_EN.update({
    'settings': '设置 / 选项', 'preferences': '偏好设置', 'account': '账户',
    'subscription': '订阅', 'billing': '计费 / 账单', 'notification': '通知',
    'privacy': '隐私', 'security': '安全', 'theme': '主题', 'dark': '深色',
    'light': '浅色', 'automatic': '自动', 'region': '地区', 'shortcut': '快捷键',
    'accessibility': '辅助功能', 'resolution': '分辨率', 'proxy': '代理',
    'firewall': '防火墙', 'update': '更新', 'upgrade': '升级', 'downgrade': '降级',
    'install': '安装', 'uninstall': '卸载', 'version': '版本', 'license': '许可证',
    'activate': '激活', 'deactivate': '停用', 'login': '登录', 'logout': '退出登录',
    'profile': '个人资料 / 配置', 'avatar': '头像', 'backup': '备份', 'restore': '恢复',
    'sync': '同步', 'export': '导出', 'import': '导入', 'cache': '缓存',
    'clear': '清除', 'default': '默认', 'advanced': '高级', 'basic': '基本',
    'general': '常规', 'about': '关于', 'quit': '退出', 'restart': '重启',
    'hide': '隐藏', 'show': '显示', 'minimize': '最小化', 'maximize': '最大化',
    'window': '窗口', 'tab': '标签页', 'toolbar': '工具栏', 'sidebar': '侧边栏',
    'menu': '菜单', 'icon': '图标', 'button': '按钮', 'toggle': '开关 / 切换',
    'switch': '开关 / 切换', 'slider': '滑块', 'dropdown': '下拉菜单',
    'checkbox': '复选框', 'radio': '单选按钮', 'search': '搜索', 'filter': '筛选 / 过滤',
    'sort': '排序', 'select': '选择', 'deselect': '取消选择', 'resize': '调整大小',
    'scroll': '滚动', 'zoom': '缩放', 'pan': '平移', 'rotate': '旋转', 'undo': '撤销',
    'redo': '重做', 'cut': '剪切', 'copy': '复制', 'paste': '粘贴', 'insert': '插入',
    'replace': '替换', 'delete': '删除', 'previous': '上一个', 'next': '下一个',
    'cancel': '取消', 'confirm': '确认', 'apply': '应用', 'save': '保存',
    'discard': '放弃 / 丢弃', 'reset': '重置', 'submit': '提交', 'upload': '上传',
    'download': '下载', 'attach': '附加', 'preview': '预览', 'print': '打印',
    'share': '分享', 'bookmark': '书签', 'favorite': '收藏', 'recent': '最近',
    'history': '历史记录', 'status': '状态', 'error': '错误', 'warning': '警告',
    'info': '信息', 'success': '成功', 'failed': '失败', 'pending': '待处理',
    'queued': '排队中', 'paused': '已暂停', 'completed': '已完成', 'progress': '进度',
    'remaining': '剩余', 'done': '完成', 'ready': '就绪', 'connecting': '连接中',
    'connected': '已连接', 'disconnected': '已断开', 'loading': '加载中',
    'processing': '处理中', 'analyzing': '分析中', 'indexing': '索引中',
    'installing': '安装中', 'permanent': '永久', 'temporary': '临时',
    'local': '本地', 'cloud': '云 / 云端', 'device': '设备', 'laptop': '笔记本电脑',
    'desktop': '桌面 / 台式机', 'tablet': '平板电脑', 'compatible': '兼容的',
    'required': '必需的', 'optional': '可选的', 'recommended': '推荐的',
    'disabled': '已禁用', 'enabled': '已启用', 'locked': '已锁定', 'unlocked': '已解锁',
    'readonly': '只读', 'hidden': '隐藏的', 'visible': '可见的', 'browse': '浏览',
    'navigate': '导航', 'refresh': '刷新', 'reload': '重新加载', 'terminate': '终止',
    'kill': '结束进程 / 终止', 'pause': '暂停', 'resume': '继续', 'retry': '重试',
    'abort': '中止', 'interrupt': '中断', 'timeout': '超时', 'offline': '离线',
    'online': '在线', 'model': '模型', 'prompt': '提示词 / 提示', 'response': '响应 / 回答',
    'reasoning': '推理 / 思考', 'analysis': '分析', 'approach': '方法 / 途径',
    'consider': '考虑', 'alternative': '替代方案', 'however': '然而', 'therefore': '因此',
    'thus': '因此 / 从而', 'hence': '因此', 'moreover': '此外', 'furthermore': '此外 / 而且',
    'consequently': '因此 / 结果', 'additionally': '另外', 'finally': '最后',
    'overall': '总的来说', 'conclusion': '结论', 'assumption': '假设',
    'hypothesis': '假设 / 假说', 'verify': '验证 / 核实', 'validate': '校验',
    'explanation': '解释', 'detail': '细节', 'instance': '实例', 'scenario': '场景',
    'context': '上下文 / 语境', 'meaning': '含义', 'intent': '意图', 'objective': '目标',
    'purpose': '目的', 'constraint': '约束', 'limitation': '限制', 'tradeoff': '权衡 / 取舍',
    'compromise': '折中', 'solution': '解决方案', 'decision': '决策', 'choice': '选择',
    'comparison': '比较', 'contrast': '对比', 'similarity': '相似性', 'difference': '差异',
    'advantage': '优点', 'disadvantage': '缺点', 'benefit': '好处 / 收益',
    'drawback': '缺点', 'risk': '风险', 'cost': '成本', 'performance': '性能',
    'efficiency': '效率', 'optimize': '优化', 'improve': '改进', 'enhance': '增强',
    'reduce': '减少', 'increase': '增加', 'balance': '平衡', 'prioritize': '优先级排序',
    'organize': '组织 / 整理', 'structure': '结构', 'group': '分组', 'classify': '分类',
    'categorize': '分类', 'summarize': '总结', 'simplify': '简化', 'clarify': '澄清',
    'elaborate': '详细阐述', 'expand': '扩展', 'specify': '指定 / 明确',
    'generalize': '泛化', 'abstract': '抽象', 'concrete': '具体的', 'implement': '实现',
    'execute': '执行', 'compile': '编译', 'deploy': '部署', 'release': '发布 / 版本',
    'maintain': '维护', 'migrate': '迁移', 'convert': '转换', 'transform': '变换 / 转换',
    'suggest': '建议', 'recommend': '推荐', 'explain': '解释', 'describe': '描述',
    'illustrate': '说明 / 图示', 'define': '定义', 'attempt': '尝试', 'ensure': '确保',
    'guarantee': '保证', 'require': '需要 / 要求', 'derive': '推导', 'infer': '推断',
    'deduce': '推断', 'conclude': '得出结论', 'prove': '证明', 'assume': '假定',
    'presume': '假设', 'estimate': '估计', 'roughly': '大致 / 粗略',
    'approximately': '大约', 'exactly': '确切地', 'generally': '通常',
    'typically': '通常', 'usually': '通常', 'rarely': '很少', 'frequently': '频繁地',
    'occasionally': '偶尔', 'sometimes': '有时', 'potentially': '可能地',
    'probably': '很可能', 'possibly': '可能', 'definitely': '肯定', 'certainly': '当然',
    'likely': '可能的', 'unlikely': '不太可能的', 'undefined': '未定义',
    'null': '空值', 'nil': '空值', 'exception': '异常', 'throw': '抛出',
    'catch': '捕获', 'return': '返回', 'break': '跳出 / 中断', 'continue': '继续',
    'loop': '循环', 'iterate': '迭代', 'array': '数组', 'list': '列表',
    'dictionary': '字典', 'map': '映射', 'set': '集合', 'queue': '队列', 'stack': '栈',
    'heap': '堆', 'tree': '树', 'graph': '图', 'node': '节点', 'edge': '边',
    'pointer': '指针', 'reference': '引用', 'value': '值 / 价值', 'type': '类型',
    'generic': '泛型', 'closure': '闭包', 'callback': '回调', 'promise': 'Promise / 期约',
    'async': '异步', 'await': '等待 / await', 'event': '事件', 'handler': '处理器',
    'delegate': '委托', 'protocol': '协议', 'interface': '接口', 'class': '类',
    'struct': '结构体', 'enum': '枚举', 'function': '函数', 'method': '方法',
    'property': '属性', 'variable': '变量', 'constant': '常量', 'parameter': '参数',
    'argument': '实参 / 参数', 'void': '无返回值', 'boolean': '布尔值',
    'integer': '整数', 'float': '浮点数', 'double': '双精度浮点数', 'string': '字符串',
    'character': '字符', 'byte': '字节', 'bit': '位', 'binary': '二进制',
    'decimal': '十进制', 'hexadecimal': '十六进制', 'octal': '八进制',
    'syntax': '语法', 'semantics': '语义', 'interpret': '解释', 'runtime': '运行时',
    'debug': '调试', 'debugger': '调试器', 'breakpoint': '断点', 'watch': '监视',
    'trace': '跟踪', 'log': '日志', 'logger': '日志器', 'crash': '崩溃',
    'segfault': '段错误', 'leak': '泄漏', 'memory': '内存', 'thread': '线程',
    'process': '进程', 'mutex': '互斥锁', 'lock': '锁', 'deadlock': '死锁',
    'concurrency': '并发', 'parallel': '并行', 'serial': '串行', 'synchronous': '同步',
    'asynchronous': '异步', 'nonblocking': '非阻塞', 'blocking': '阻塞',
    'dependency': '依赖', 'dependencies': '依赖项', 'package': '包', 'module': '模块',
    'library': '库', 'framework': '框架', 'toolkit': '工具包', 'endpoint': '接口端点',
    'request': '请求', 'header': '请求头', 'payload': '负载 / 数据', 'query': '查询',
    'schema': '模式 / 结构', 'serialize': '序列化', 'deserialize': '反序列化',
    'parse': '解析', 'parsing': '解析', 'encode': '编码', 'decode': '解码',
    'hash': '哈希', 'encrypt': '加密', 'decrypt': '解密', 'authentication': '认证 / 身份验证',
    'authorization': '授权', 'token': '令牌', 'session': '会话', 'cookie': 'Cookie',
    'credential': '凭证', 'register': '注册', 'verify': '验证', 'if': '如果 / 条件判断',
    'else': '否则', 'elif': '否则如果', 'switch': '分支 / 切换', 'case': '情况 / 分支',
    'for': '对于 / 循环', 'while': '当…时 / 循环', 'repeat': '重复', 'until': '直到',
    'where': '哪里 / 条件', 'join': '连接', 'inner': '内连接', 'outer': '外连接',
    'full': '全', 'cross': '交叉', 'union': '并集 / 联合', 'alter': '修改',
    'drop': '删除 / 丢弃', 'truncate': '截断', 'grant': '授予', 'revoke': '撤销',
    'transaction': '事务', 'commit': '提交', 'rollback': '回滚', 'begin': '开始',
    'end': '结束', 'declare': '声明', 'inherit': '继承', 'override': '重写 / 覆盖',
    'overload': '重载', 'static': '静态的', 'dynamic': '动态的', 'global': '全局的',
    'constructor': '构造函数', 'destructor': '析构函数', 'initializer': '初始化器',
    'public': '公开的', 'private': '私有的', 'protected': '受保护的', 'internal': '内部的',
    'virtual': '虚的', 'final': '最终的', 'const': '常量', 'let': '声明变量',
    'var': '变量', 'new': '新建', 'sizeof': '取大小', 'typeof': '类型判断',
    'instanceof': '类型检查', 'repo': '代码仓库', 'repository': '代码仓库',
    'branch': '分支', 'merge': '合并', 'rebase': '变基', 'pull': '拉取',
    'push': '推送', 'fetch': '获取', 'clone': '克隆', 'fork': '复刻 / 派生',
    'checkout': '切换分支', 'stash': '暂存', 'tag': '标签', 'remote': '远程仓库',
    'origin': '远程源', 'upstream': '上游', 'main': '主分支', 'master': '主分支',
    'feature': '功能分支', 'hotfix': '热修复', 'issue': '问题 / 议题',
    'linter': '代码检查工具', 'formatter': '代码格式化工具', 'test': '测试',
    'coverage': '覆盖率', 'benchmark': '基准测试', 'profile': '性能分析',
    'pipeline': '流水线', 'artifact': '构建产物', 'build': '构建', 'link': '链接',
    'loader': '加载器', 'compiler': '编译器', 'interpreter': '解释器',
    'assembler': '汇编器', 'bytecode': '字节码', 'script': '脚本',
    'configuration': '配置', 'config': '配置', 'environment': '环境', 'dev': '开发',
    'staging': '预发布环境', 'production': '生产环境', 'localhost': '本地主机',
    'server': '服务器', 'client': '客户端', 'backend': '后端', 'frontend': '前端',
    'database': '数据库', 'table': '数据表', 'index': '索引', 'row': '行',
    'column': '列', 'key': '键', 'field': '字段', 'record': '记录',
    'shard': '分片', 'replica': '副本', 'container': '容器', 'microservice': '微服务',
    'monolith': '单体应用', 'serverless': '无服务器', 'lambda': 'Lambda 函数',
    'scale': '扩展 / 缩放', 'websocket': 'WebSocket 协议', 'graphql': 'GraphQL 查询语言',
    'kafka': 'Kafka 消息系统', 'redis': 'Redis 缓存', 'migration': '数据库迁移',
    'seed': '种子数据', 'idempotent': '幂等的', 'immutable': '不可变的',
    'mutable': '可变的', 'nullable': '可空的', 'deprecated': '已弃用',
    'obsolete': '过时的', 'legacy': '遗留 / 旧版', 'refactor': '重构',
    'boilerplate': '样板代码', 'regression': '回归问题', 'requirement': '需求',
    'spec': '规格说明', 'architecture': '架构', 'pattern': '模式',
    'anti-pattern': '反模式', 'abstraction': '抽象', 'encapsulation': '封装',
    'polymorphism': '多态', 'inheritance': '继承', 'modularity': '模块化',
    'scalability': '可扩展性', 'reliability': '可靠性', 'availability': '可用性',
    'latency': '延迟', 'throughput': '吞吐量', 'bandwidth': '带宽', 'disk': '磁盘',
    'storage': '存储', 'browser': '浏览器', 'web': '网页', 'website': '网站',
    'page': '页面', 'element': '元素', 'layout': '布局', 'style': '样式',
    'selector': '选择器', 'render': '渲染', 'animation': '动画', 'transition': '过渡',
    'responsive': '响应式', 'viewport': '视口', 'grid': '网格', 'flexbox': '弹性布局',
    'padding': '内边距', 'margin': '外边距', 'border': '边框', 'background': '背景',
    'color': '颜色', 'font': '字体', 'size': '大小', 'width': '宽度', 'height': '高度',
    'position': '位置', 'absolute': '绝对定位', 'relative': '相对定位',
    'fixed': '固定定位', 'sticky': '粘性定位', 'overflow': '溢出', 'opacity': '不透明度',
    'shadow': '阴影', 'gradient': '渐变', 'interactive': '交互的', 'accessible': '无障碍的',
    'usability': '可用性', 'component': '组件', 'state': '状态', 'props': '属性',
    'hook': '钩子函数', 'reactive': '响应式的', 'declarative': '声明式',
    'imperative': '命令式', 'data binding': '数据绑定', 'virtual dom': '虚拟 DOM',
    'event loop': '事件循环', 'buffer': '缓冲区', 'stream': '流', 'socket': '套接字',
    'network': '网络', 'protocol': '协议', 'packet': '数据包', 'dns': '域名系统',
    'certificate': '证书', 'encryption': '加密', 'vpn': '虚拟专用网络',
    'port': '端口', 'subnet': '子网', 'gateway': '网关', 'router': '路由器',
    'algorithm': '算法', 'recursion': '递归', 'memoization': '记忆化',
    'backtracking': '回溯', 'greedy': '贪心', 'heuristic': '启发式',
    'encapsulate': '封装', 'aggregate': '聚合', 'composition': '组合',
    'serialization': '序列化', 'deserialization': '反序列化', 'pagination': '分页',
    'throttle': '节流', 'debounce': '防抖', 'polling': '轮询', 'streaming': '流式',
    'batch': '批处理', 'cron': '定时任务', 'daemon': '守护进程', 'cacheable': '可缓存的',
    'checksum': '校验和', 'callbackhell': '回调地狱', 'monkey patch': '猴子补丁',
    'hot reload': '热重载', 'hot swap': '热替换', 'graceful shutdown': '优雅关闭',
    'graceful degradation': '优雅降级', 'failover': '故障转移', 'round robin': '轮询算法',
    'hashing': '哈希计算', 'collision': '冲突 / 碰撞', 'probing': '探测',
    'sparse': '稀疏的', 'dense': '稠密的', 'sorted': '已排序的',
    'recursive': '递归的', 'iterative': '迭代的', 'stack overflow': '栈溢出',
    'first in first out': '先进先出', 'last in first out': '后进先出',
    'priority queue': '优先队列', 'double linked list': '双向链表',
    'balanced tree': '平衡树', 'red black tree': '红黑树', 'avl tree': 'AVL 平衡树',
    'trie': '前缀树', 'segment tree': '线段树', 'heap sort': '堆排序',
    'merge sort': '归并排序', 'quick sort': '快速排序', 'insertion sort': '插入排序',
    'selection sort': '选择排序', 'bubble sort': '冒泡排序', 'radix sort': '基数排序',
    'topological sort': '拓扑排序', 'shortest path': '最短路径',
    'minimum spanning tree': '最小生成树', 'maximum flow': '最大流',
    'bitmask': '位掩码', 'bitwise': '按位', 'shift operator': '移位运算符',
    'logical operator': '逻辑运算符', 'comparison operator': '比较运算符',
    'assignment operator': '赋值运算符', 'unary operator': '一元运算符',
    'binary operator': '二元运算符', 'ternary operator': '三元运算符',
    'operator overloading': '运算符重载', 'method overloading': '方法重载',
    'dynamic dispatch': '动态分派', 'static dispatch': '静态分派',
    'early binding': '早期绑定', 'late binding': '晚期绑定',
    'type erasure': '类型擦除', 'boxing': '装箱', 'unboxing': '拆箱',
    'autoboxing': '自动装箱', 'weak reference': '弱引用', 'strong reference': '强引用',
    'unowned reference': '无主引用', 'retain cycle': '循环引用',
    'deinit': '析构', 'lazy initialization': '懒加载初始化',
    'early exit': '提前退出', 'guard clause': '卫语句',
    'code block': '代码块', 'scope': '作用域', 'namespace': '命名空间',
    'access modifier': '访问修饰符', 'visibility': '可见性',
    'default value': '默认值', 'sentinel': '哨兵值', 'magic number': '魔法数字',
    'hard coded': '硬编码的', 'hardcode': '硬编码', 'fire and forget': '发后即忘',
    'best practice': '最佳实践', 'worst case': '最坏情况', 'best case': '最好情况',
    'average case': '平均情况', 'brute force': '暴力破解 / 暴力法',
    'try catch': 'try-catch 异常处理', 'if else': 'if-else 条件判断',
    'for loop': 'for 循环', 'while loop': 'while 循环', 'do while': 'do-while 循环',
    'switch case': 'switch-case 分支', 'switch statement': 'switch 语句',
    'if statement': 'if 语句', 'loop condition': '循环条件', 'loop body': '循环体',
    'infinite loop': '无限循环', 'nested loop': '嵌套循环', 'array index': '数组下标',
    'out of bounds': '越界', 'index out of range': '下标越界',
    'division by zero': '除以零', 'divide by zero': '除以零',
})

PROG_ZH = {
    '编程': 'programming / coding', '程序': 'program', '代码': 'code',
    '调试': 'debug', '编译': 'compile', '运行': 'run / execute', '执行': 'execute',
    '部署': 'deploy', '发布': 'release / publish', '版本': 'version', '分支': 'branch',
    '合并': 'merge', '提交': 'commit', '推送': 'push', '拉取': 'pull', '克隆': 'clone',
    '仓库': 'repository', '服务器': 'server', '数据库': 'database', '网络': 'network',
    '接口': 'interface / API', '请求': 'request', '响应': 'response', '异常': 'exception',
    '错误': 'error', '警告': 'warning', '日志': 'log', '缓存': 'cache',
    '配置': 'configuration', '环境': 'environment', '生产环境': 'production',
    '开发': 'development', '测试': 'test', '自动化': 'automation', '构建': 'build',
    '打包': 'package', '安装': 'install', '卸载': 'uninstall', '升级': 'upgrade',
    '依赖': 'dependency', '框架': 'framework', '组件': 'component', '函数': 'function',
    '变量': 'variable', '常量': 'constant', '数组': 'array', '对象': 'object',
    '类': 'class', '方法': 'method', '属性': 'property', '算法': 'algorithm',
    '数据结构': 'data structure', '排序': 'sort', '搜索': 'search', '递归': 'recursion',
    '迭代': 'iteration', '指针': 'pointer', '引用': 'reference', '内存': 'memory',
    '线程': 'thread', '进程': 'process', '锁': 'lock', '死锁': 'deadlock',
    '并发': 'concurrency', '异步': 'asynchronous', '同步': 'synchronous',
    '回调': 'callback', '事件': 'event', '协议': 'protocol', '安全': 'security',
    '加密': 'encryption', '认证': 'authentication', '授权': 'authorization',
    '权限': 'permission', '用户': 'user', '账号': 'account', '密码': 'password',
    '登录': 'login', '注册': 'register', '验证': 'verify', '下载': 'download',
    '上传': 'upload', '同步': 'sync', '备份': 'backup', '恢复': 'restore',
    '设置': 'settings', '偏好': 'preferences', '主题': 'theme', '深色': 'dark mode',
    '浅色': 'light mode', '快捷键': 'shortcut', '通知': 'notification',
    '隐私': 'privacy', '更新': 'update', '文档': 'documentation', '教程': 'tutorial',
    '示例': 'example', '样例': 'sample', '参考': 'reference', '帮助': 'help',
    '说明': 'explanation', '手册': 'manual', '指南': 'guide', '开源': 'open source',
    '机器学习': 'machine learning', '人工智能': 'artificial intelligence',
    '大语言模型': 'large language model', '神经网络': 'neural network',
    '深度学习': 'deep learning', '自然语言处理': 'natural language processing',
    '用户界面': 'user interface', '命令行': 'command line', '版本控制': 'version control',
    '源代码': 'source code', '单元测试': 'unit test', '集成测试': 'integration test',
    '代码审查': 'code review', '设计模式': 'design pattern', '数据库': 'database',
    '云': 'cloud', '云计算': 'cloud computing', '微服务': 'micro service',
    '容器': 'container', '前端': 'frontend', '后端': 'backend', '全栈': 'full stack',
    '算法复杂度': 'algorithm complexity', '时间复杂度': 'time complexity',
    '空间复杂度': 'space complexity', '面向对象': 'object-oriented',
    '函数式': 'functional', '编译错误': 'compile error', '运行时错误': 'runtime error',
    '异常处理': 'exception handling', '错误处理': 'error handling', '重构': 'refactor',
    '技术债': 'technical debt', '代码异味': 'code smell', '依赖注入': 'dependency injection',
    '垃圾回收': 'garbage collection', '内存泄漏': 'memory leak', '竞态条件': 'race condition',
}

PROG_DICT = (PROG_EN, PROG_ZH)

if __name__ == '__main__':
    main()
