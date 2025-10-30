# Ubuntu_Script
Скрипты для развертывания


## Yandex repository
``` shell
curl -fsSL https://repo.yandex.ru/yandex-browser/YANDEX-BROWSER-KEY.GPG | sudo gpg --dearmor -o /etc/apt/keyrings/yandex-browser.gpg
```

``` shell
sudo wget -qO https://repo.yandex.ru/yandex-browser/YANDEX-BROWSER-KEY.GPG /etc/apt/trusted.gpg.d/yandex-browser.asc
```

``` shell
deb [arch=amd64] http://repo.yandex.ru/yandex-browser/deb stable main" | sudo tee /etc/apt/sources.list.d/yandex-stable.list
```
