import psutil
import time
import threading
import multiprocessing
import os
import math
import random
import array

# ================= 配置参数 =================
BASE_TARGET_CPU = 50.0   # 目标总 CPU 占用率 (%)
START_THRESHOLD = 15.0    # 启动阈值 (略微调高，确保业务低迷时才触发)
STOP_THRESHOLD = 75.0     # 停止阈值 (保护业务，超过此值脚本立即停工)
CHECK_INTERVAL = 1.5      # 检测频率
# ===========================================

class OCISmartGuardian:
    def __init__(self):
        self.active = False
        self.keep_running = True
        self.num_cores = multiprocessing.cpu_count()
        self.load_factor = 0.05
        
        # PID 调节参数
        self.Kp = 0.008 
        self.Ki = 0.001
        self.integral = 0.0
        
        # 创建一个小型的活跃缓冲区 (1MB)，用于模拟内存读写
        # 既能产生内存活跃信号，又不会导致 OOM
        self.active_buffer = array.array('i', range(256 * 1024)) 

    def get_dynamic_target(self):
        """生成随时间轻微波动的目标值，模拟真实业务特征"""
        hour = time.localtime().tm_hour
        sin_wave = 3 * math.sin(math.pi * hour / 12)
        noise = random.uniform(-2, 2)
        return BASE_TARGET_CPU + sin_wave + noise

    def busy_worker(self):
        """核心逻辑：在计算的同时进行内存随机读写"""
        buffer_len = len(self.active_buffer)
        
        while self.keep_running:
            if self.active:
                start_time = time.perf_counter()
                
                # 动态计算周期
                cycle_len = random.uniform(0.08, 0.12)
                work_time = cycle_len * self.load_factor
                
                while (time.perf_counter() - start_time) < work_time:
                    # 1. 浮点运算 (CPU 消耗)
                    _ = math.sqrt(random.random() * 100)
                    
                    # 2. 内存读写 (内存活跃)
                    # 随机修改缓冲区中的一个位置，产生内存写入流量
                    idx = random.randint(0, buffer_len - 1)
                    self.active_buffer[idx] = idx ^ 0xAF
                
                # 剩余时间释放 CPU
                sleep_time = cycle_len * (1.0 - self.load_factor)
                if sleep_time > 0:
                    time.sleep(sleep_time)
            else:
                # 避让模式：完全静默
                time.sleep(CHECK_INTERVAL)

    def monitor(self):
        print("OCI Smart Guardian (业务保护版) 已启动")
        print(f"监测到核心数: {self.num_cores} | 当前业务已占内存: {psutil.virtual_memory().percent}%")
        
        while self.keep_running:
            try:
                # 获取系统总 CPU 占用
                current_total_cpu = psutil.cpu_percent(interval=CHECK_INTERVAL)
                dynamic_target = self.get_dynamic_target()
                
                # 内存保护检查：如果剩余可用内存低于 10%，强制进入避让模式
                mem_available_pct = psutil.virtual_memory().available * 100 / psutil.virtual_memory().total
                
                # 逻辑判断：CPU 过高 或 内存告急 时停止
                if current_total_cpu > STOP_THRESHOLD or mem_available_pct < 10.0:
                    if self.active:
                        self.active = False
                        self.integral = 0
                        # print("触发保护模式：避让业务资源")
                elif current_total_cpu < START_THRESHOLD:
                    if not self.active:
                        self.active = True
                        # print("系统空闲：开始维持负载")

                # 如果处于激活状态，微调负载因子
                if self.active:
                    error = dynamic_target - current_total_cpu
                    self.integral = max(-100, min(100, self.integral + error))
                    adjustment = (self.Kp * error) + (self.Ki * self.integral)
                    self.load_factor = max(0.01, min(0.90, self.load_factor + adjustment))

            except Exception as e:
                # print(f"监控异常: {e}")
                time.sleep(5)

    def run(self):
        threads = []
        for i in range(self.num_cores):
            t = threading.Thread(target=self.busy_worker, daemon=True)
            t.start()
            threads.append(t)

        try:
            self.monitor()
        except KeyboardInterrupt:
            self.keep_running = False
            print("\n已退出。")

if __name__ == "__main__":
    # 设置进程优先级为最低
    try:
        os.nice(19) 
    except:
        pass
        
    guardian = OCISmartGuardian()
    guardian.run()
