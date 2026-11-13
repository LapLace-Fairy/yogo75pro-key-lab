# 第三方资料

设备协议参考 [YogoDot](https://github.com/Wednesque/yogodot) 和其 [Go 移植版](https://github.com/juning98/yogodot_go)，两者采用 MIT 许可证；报文布局实现依据其协议设计。协议研究另参考 [atk-yogo75-tool](https://github.com/lore2601/atk-yogo75-tool) 和 [rossgpt/yogo](https://github.com/rossgpt/yogo)。后者将 `0x3C` 描述为易失性流，将 `0x3B` 描述为持久写入；YogoDot 对 `0x3B` 的持久性描述不同，因此实时显示采用 `0x3C`，不在运行时调用 `0x3B`。

## YogoDot MIT License

Copyright (c) 2026 YogoDot contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
