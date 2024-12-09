#!/bin/bash

# 로그 파일 위치
LOG_DIR="/home/master/make_user_log"
LOG_FILE="$LOG_DIR/user.log"

# 로그 디렉터리가 존재하지 않으면 생성
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    echo "$(date) - 로그 디렉터리 ($LOG_DIR) 생성" >> "$LOG_FILE"
fi

# 사용자 입력 받기
read -p "새로운 사용자 이름을 입력하세요: " username

# getent을 사용하여 사용자가 존재하는지 확인
if getent passwd "$username" > /dev/null 2>&1; then
    echo "$(date) - 오류: 사용자 '$username' 이미 존재" >> "$LOG_FILE"
    echo "사용자가 이미 존재합니다."
    exit 1
else
    # 새 사용자 추가
    useradd -m -s /bin/bash "$username"
    if [ $? -eq 0 ]; then
        echo "$(date) - 정보: 사용자 '$username' 생성 성공" >> "$LOG_FILE"
    else
        echo "$(date) - 오류: 사용자 '$username' 생성 실패" >> "$LOG_FILE"
        exit 1
    fi
fi

# 초기 비밀번호 설정: 사용자 이름을 비밀번호로 설정
echo "$username:$username" | chpasswd
if [ $? -eq 0 ]; then
    echo "$(date) - 정보: '$username' 사용자에게 초기 비밀번호 '$username' 설정 성공" >> "$LOG_FILE"
else
    echo "$(date) - 오류: '$username' 사용자에 대한 초기 비밀번호 설정 실패" >> "$LOG_FILE"
    exit 1
fi

# 최초 접속 시 비밀번호 변경을 강제하는 설정
chage -d 0 "$username"
if [ $? -eq 0 ]; then
    echo "$(date) - 정보: '$username' 사용자에 대해 비밀번호 변경 강제 설정" >> "$LOG_FILE"
else
    echo "$(date) - 오류: '$username' 사용자에 대한 비밀번호 변경 강제 설정 실패" >> "$LOG_FILE"
    exit 1
fi

# 새로운 사용자 홈 디렉터리 내에 homepage 디렉터리 생성
mkdir -p /home/"$username"/homepage
if [ $? -eq 0 ]; then
    echo "$(date) - 정보: '$username'의 /home/$username/homepage 디렉터리 생성 성공" >> "$LOG_FILE"
else
    echo "$(date) - 오류: '$username'의 /home/$username/homepage 디렉터리 생성 실패" >> "$LOG_FILE"
    exit 1
fi

# 000-default.conf 파일 백업
mkdir -p "/etc/apache2/sites-available/$username/"
BACKUP_FILE="/etc/apache2/sites-available/$username/000-default.conf_$(date +%Y-%m-%d_%H-%M-%S)_bak"
cp -arp /etc/apache2/sites-available/000-default.conf "$BACKUP_FILE"
if [ $? -eq 0 ]; then
    echo "$(date) - 정보: 000-default.conf 파일 백업 성공: $BACKUP_FILE" >> "$LOG_FILE"
else
    echo "$(date) - 오류: 000-default.conf 파일 백업 실패" >> "$LOG_FILE"
    exit 1
fi

# 확인 메시지
echo "디렉터리 및 파일 백업 완료: $BACKUP_FILE"

# 사용자 홈페이지를 위한 Apache 설정 추가
APACHE_CONF="/etc/apache2/sites-available/000-default.conf"

# Alias와 Directory 설정 내용
APACHE_CONFIG=" 
Alias /$username /var/www/html/$username/homepage
<Directory /var/www/$username>
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
"

# /etc/apache2/sites-available/000-default.conf에 이미 설정이 있는지 확인
if grep -q "Alias /$username" "$APACHE_CONF"; then
    echo "$(date) - 정보: '$username'에 대한 Apache 설정이 이미 존재합니다." >> "$LOG_FILE"
else
    # </VirtualHost> 태그 바로 위에 설정 추가
    sudo awk -v config="$APACHE_CONFIG" '
        /<\/VirtualHost>/ { 
            print config 
        } 
        { print } 
    ' "$APACHE_CONF" > "$APACHE_CONF.tmp" && sudo mv "$APACHE_CONF.tmp" "$APACHE_CONF"
    if [ $? -eq 0 ]; then
        echo "$(date) - 정보: '$username'에 대한 Apache 설정 추가 성공" >> "$LOG_FILE"
    else
        echo "$(date) - 오류: '$username'에 대한 Apache 설정 추가 실패" >> "$LOG_FILE"
        exit 1
    fi
fi

# Apache 서비스 재시작 (설정 적용)
systemctl restart apache2
if [ $? -eq 0 ]; then
    echo "$(date) - 정보: Apache 서버 재시작 성공" >> "$LOG_FILE"
else
    echo "$(date) - 오류: Apache 서버 재시작 실패" >> "$LOG_FILE"
    exit 1
fi

# 사용자에게 알림
echo "사용자 '$username'가 성공적으로 생성되었습니다."
echo "비밀번호를 최초 로그인 시 변경해야 합니다."
echo "Apache 설정이 성공적으로 추가되었습니다."

# 사용자마다 index.html 홈페이지 생성
USER_VAR_HOME="/var/www/html"
mkdir -p "$USER_VAR_HOME/$username/homepage"

# 사용자 홈페이지 파일 생성
echo "<html><body><h1>Welcome to $username's homepage!</h1></body></html>" > "$USER_VAR_HOME/$username/homepage/index.html"

# 로그 생성
if [ $? -eq 0 ]; then
    echo "$(date) - 정보: '$username'의 $USER_VAR_HOME/$username 디렉터리 생성 성공" >> "$LOG_FILE"
else
    echo "$(date) - 오류: '$username'의 $USER_VAR_HOME/$username 디렉터리 생성 실패" >> "$LOG_FILE"
    exit 1
fi

# /home/$username/homepage/index.html을 /var/www/html/$username/homepage로 소프트 링크 생성
ln -s /var/www/html/$username/homepage/index.html /home/"$username"/homepage/index.html

# 사용자가 자신의 홈 디렉터리만 접근 가능하도록 설정
chown "$username":"$username" /home/"$username"  # 사용자에게 홈 디렉터리 소유권 부여
chmod 700 /home/"$username"  # 사용자에게만 읽기, 쓰기, 실행 권한 부여

# /home 디렉터리 및 상위 폴더의 접근 제한
chmod o-r /home  # /home에 대한 다른 사용자의 읽기 권한 제거
chmod o-x /home  # /home에 대한 다른 사용자의 실행 권한 제거

# 사용자가 자신의 homepage만 접근 가능하도록 설정
chmod 755 /home/"$username"/homepage  # 사용자에게만 읽기, 쓰기, 실행 권한 부여
chown -R $username:$username /home/"$username"/homepage  # 사용자에게만 읽기, 쓰기, 실행 권한 부여

