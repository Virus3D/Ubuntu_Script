# Ubuntu_Script
Скрипты для развертывания


## Yandex repository

``` shell
sudo wget -O /etc/apt/trusted.gpg.d/yandex-browser.asc https://repo.yandex.ru/yandex-browser/YANDEX-BROWSER-KEY.GPG
```

``` shell
 echo "deb [arch=amd64] http://repo.yandex.ru/yandex-browser/deb stable main" | sudo tee /etc/apt/sources.list.d/yandex-stable.list
```
