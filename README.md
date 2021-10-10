# tae-kim_cn_latex_go

一个将[《日语语法指南》](http://res.wokanxing.info/jpgramma/) 转换为pdf的小工具。此工具fork自 Philipp Kerling 写的 [Perl 工具](https://github.com/bobbens/tae-kim_latex)。

## 用法
在安装了tex、golang等环境后，直接运行：
```
make
```

备忘：

```
# 安装texlive
sudo pacman -S texlive-most texlive-langchinese # Arch Linux
sudo apt install texlive texlive-lang-chinese texlive-xetex # Debian系

# 安装字体
sudo pacman -S ttf-linux-libertine adobe-source-han-serif-otc-fonts # Arch Linux
sudo apt install fonts-linuxlibertine fonts-noto-cjk # Debian系
```

对于Arch系，字体名称可能和Debian系的不同。如果遇到了无法找到字体的情况，请编辑sty文件，修改为下列字体：
```
\setmainfont{Linux Biolinum O}
\setCJKmainfont[AutoFakeSlant]{Source Han Serif SC}
\setCJKsansfont{Source Han Sans SC}
```

## 成品

请访问[Release页面](https://github.com/jim-kirisame/jpgramma-cn-pdf-converter/releases/latest)下载转换完毕的pdf文件。
