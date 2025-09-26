Написать скрипт на bash для мониторинга процесса test в среде linux. Скрипт должен отвечать следующим требованиям:</br>
1. Запускаться при запуске системы (предпочтительно написать юнит
systemd в дополнение к скрипту)</br>
2. Отрабатывать каждую минуту</br>
3. Если процесс запущен, то стучаться(по https) на
https://test.com/monitoring/test/api</br>
4. Если процесс был перезапущен, писать в лог /var/log/monitoring.log
(если процесс не запущен, то ничего не делать)</br>
5. Если сервер мониторинга не доступен, так же писать в лог.
Решение присылать ссылкой на свой git-репозиторий в Github/Gitlab.</br>
</br>
</br>
В начале создаю файл /usr/local/bin/process_monitor.sh
</br>
#!/bin/bash
</br>
# Лог-файл
LOG_FILE="/var/log/monitoring.log"
</br>
# Проверяю наличие запущенного процесса 'test'
if pgrep -f 'test' > /dev/null ; then
    # Процесс найден, отправляю POST запрос
    # --max-time 5 ограничит ожидание сервера максимум пятью секундами.
    # -sSfL отключает вывод стандартных сообщений и выводит статусный код HTTP
    # Если код ответа начинается с цифры 2, значит всё хорошо (например, успешный ответ 200 OK), иначе считаю сервер недоступным
    # Сообщение записываю в лог-файл с указанием текущего времени.
    if curl -sSfL --max-time 5 --output /dev/null --write-out '%{http_code}' \\
       "https://test.com/monitoring/test/api" | grep -q '^2'; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') Процесс запущен и сервер мониторинга на связи" >> "${LOG_FILE}"
    else
        echo "$(date +'%Y-%m-%d %H:%M:%S') Сервер мониторинга не на связи" >> "${LOG_FILE}"
    fi
else
    # Перезапускаю процесс
    echo "$(date +'%Y-%m-%d %H:%M:%S') Перезапуск процесса" >> "${LOG_FILE}"
    # Команда start-stop-daemon используется для запуска процесса в фоновом режиме.
    exec start-stop-daemon --start --name test --exec /путь_к_процессу_'test' &
fi
</br>
</br>
создадаю сервис unit file для systemd, который обеспечит выполнение скрипта каждую минуту. 
Создаю файл /etc/systemd/system/process-monitor.service
</br>
</br>
[Unit]
Description=Process Monitor Service for Test process
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/process_monitor.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
</br>
</br>
создаю таймер, который запустится сразу после загрузки системы и выполнит указанный выше сервис каждую минуту. Создаю файл /etc/systemd/system/process-monitor.timer
[Unit]
Description=Run Process Monitor every minute

[Timer]
OnBootSec=1min
OnCalendar=*:*:00

[Install]
WantedBy=timers.target
</br>
</br>
Делаю скрипт исполняемым
sudo chmod +x /usr/local/bin/process_monitor.sh
</br>
Перезагружаю конфигурацию systemd
sudo systemctl daemon-reload
</br>
Активирую таймер и проверяем состояние
sudo systemctl enable process-monitor.timer
sudo systemctl start process-monitor.timer
sudo systemctl list-timers
</br>
Проверяю логи, если возникли проблемы
journalctl -xe
cat /var/log/monitoring.log


