#!/bin/bash

# ================= 配置区 =================
INSTALL_DIR="/opt/oci-guardian"
SCRIPT_NAME="cpu_guardian.py"
SERVICE_NAME="oci-guardian"
# ==========================================

# 检查是否为 root 权限
if [ "$EUID" -ne 0 ]; then 
  echo "请使用 sudo 运行此脚本"
  exit
fi

echo "开始部署 OCI CPU Guardian..."

# 1. 安装系统依赖
echo "[1/5] 正在安装系统依赖..."
apt-get update -y > /dev/null
apt-get install -y python3 python3-pip python3-venv > /dev/null

# 2. 创建目录并配置环境
echo "[2/5] 正在创建工作目录: $INSTALL_DIR"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# 3. 安装 psutil (使用系统全局或创建虚拟环境)
echo "[3/5] 正在安装 Python 依赖..."
pip3 install psutil --break-system-packages || pip3 install psutil

# 4. 写入 Python 脚本
echo "[4/5] 正在生成核心 Python 脚本..."
cat << 'EOF' > $SCRIPT_NAME
import psutil
import time
import threading
import multiprocessing
import os
import math
import random
import array

# 配置参数
BASE_TARGET_CPU = 50.0   
START_THRESHOLD = 15.0    
STOP_THRESHOLD = 75.0     
CHECK_INTERVAL = 1.5      

class OCISmartGuardian:
    def __init__(self):
        self.active = False
        self.keep_running = True
        self.num_cores = multiprocessing.cpu_count()
        self.load_factor = 0.05
        self.Kp, self.Ki = 0.008, 0.001
        self.integral = 0.0
        self.active_buffer = array.array('i', range(256 * 1024)) 

    def get_dynamic_target(self):
        hour = time.localtime().tm_hour
        sin_wave = 3 * math.sin(math.pi * hour / 12)
        noise = random.uniform(-2, 2)
        return BASE_TARGET_CPU + sin_wave + noise

    def busy_worker(self):
        buffer_len = len(self.active_buffer)
        while self.keep_running:
            if self.active:
                start_time = time.perf_counter()
                cycle_len = random.uniform(0.08, 0.12)
                work_time = cycle_len * self.load_factor
                while (time.perf_counter() - start_time) < work_time:
                    _ = math.sqrt(random.random() * 100)
                    idx = random.randint(0, buffer_len - 1)
                    self.active_buffer[idx] = idx ^ 0xAF
                time.sleep(max(0, cycle_len * (1.0 - self.load_factor)))
            else:
                time.sleep(CHECK_INTERVAL)

    def monitor(self):
        while self.keep_running:
            try:
                current_total_cpu = psutil.cpu_percent(interval=CHECK_INTERVAL)
                dynamic_target = self.get_dynamic_target()
                mem_avail = psutil.virtual_memory().available * 100 / psutil.virtual_memory().total
                
                if current_total_cpu > STOP_THRESHOLD or mem_avail < 10.0:
                    self.active, self.integral = False, 0
                elif current_total_cpu < START_THRESHOLD:
                    self.active = True

                if self.active:
                    error = dynamic_target - current_total_cpu
                    self.integral = max(-100, min(100, self.integral + error))
                    adjustment = (self.Kp * error) + (self.Ki * self.integral)
                    self.load_factor = max(0.01, min(0.90, self.load_factor + adjustment))
            except Exception:
                time.sleep(5)

    def run(self):
        for _ in range(self.num_cores):
            threading.Thread(target=self.busy_worker, daemon=True).start()
        self.monitor()

if __name__ == "__main__":
    try: os.nice(19)
    except: pass
    OCISmartGuardian().run()
EOF

# 5. 创建 Systemd 服务
echo "[5/5] 正在配置系统服务..."
cat << EOF > /etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=OCI CPU and Memory Guardian
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/$SCRIPT_NAME
Restart=always
RestartSec=10
Nice=19

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl restart $SERVICE_NAME

echo "-----------------------------------------------"
echo "部署完成！"
echo "服务状态: $(systemctl is-active $SERVICE_NAME)"
echo "常用命令:"
echo "  查看实时日志: journalctl -u $SERVICE_NAME -f"
echo "  停止服务: systemctl stop $SERVICE_NAME"
echo "  查看 CPU 占用: htop"
echo "-----------------------------------------------"
