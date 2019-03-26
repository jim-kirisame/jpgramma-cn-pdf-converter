package main

import (
	"fmt"
	"image/gif"
	"image/png"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"golang.org/x/net/html"
)

var basedir = ""
var outdir = ""
var chapdir = "out/"

type context struct {
	hline bool
	cols  int
}

func errHandler(err error) {
	if err != nil {
		panic(err)
	}
}

func main() {
	if len(os.Args) != 2 {
		fmt.Println(`Usage: go-jpgrammma-latex <path-to-repo>`)
		return
	}

	dir, err := filepath.Abs(filepath.Dir(os.Args[1]))
	errHandler(err)

	basedir = dir + "/"

	file, err := os.Open(basedir + "index.html")
	errHandler(err)
	defer file.Close()

	node, err := html.Parse(file)
	errHandler(err)

	con := func(nd *html.Node) bool {
		return nd.Data == "h2" && nd.FirstChild.Data == "目录"
	}

	firstNode := getNode(node, con)

	out, err := os.OpenFile(outdir+"body.tex", os.O_CREATE|os.O_RDWR|os.O_TRUNC, 0644)
	errHandler(err)
	defer out.Close()

	walkToc(firstNode, 0, out)
}

// printNode 用于打印节点
func printNode(node *html.Node, level int) {
	if node != nil {
		for i := 0; i < level; i++ {
			fmt.Print("  ")
		}
		fmt.Println(node.Type, node.Data)

		printNode(node.FirstChild, level+1)
		printNode(node.NextSibling, level)
	}
}

// getNode 获取对应节点
func getNode(node *html.Node, condition func(*html.Node) bool) *html.Node {
	if node != nil {
		if condition(node) {
			return node
		}
		na := getNode(node.FirstChild, condition)
		if na != nil {
			return na
		}

		nb := getNode(node.NextSibling, condition)
		if nb != nil {
			return nb
		}
	}

	return nil
}

func walkToc(node *html.Node, level int, outFile *os.File) {
	if node == nil {
		return
	}

	if node.Type == html.ElementNode {
		switch node.Data {
		case "li":
			walkToc(node.FirstChild, level, outFile)
		case "ol", "ul":
			walkToc(node.FirstChild, level+1, outFile)
		case "a":
			text := node.FirstChild.Data

			// 先不处理练习部分的内容
			if strings.Contains(text, "练习") {
				for i := 0; i < level-1; i++ {
					fmt.Print("  ")
				}
				fmt.Println("-", "忽略", text)
				return
			}

			url := getAttr(node, "href")
			urlHandler(url, level, outFile, text)
		default:
			fmt.Println("Unrecognized type: ", node.Data)
		}
	}

	walkToc(node.NextSibling, level, outFile)
}

func getAttr(node *html.Node, key string) string {
	for _, item := range node.Attr {
		if item.Key == key {
			return item.Val
		}
	}
	return ""
}

func urlHandler(url string, level int, outFile *os.File, title string) {
	for i := 0; i < level-1; i++ {
		fmt.Print("  ")
	}
	fmt.Println("-", title, url)

	id := strings.TrimRight(url, ".html")
	f := outdir + chapdir + id + ".tex"
	checkDir(f)

	out, err := os.OpenFile(f, os.O_CREATE|os.O_RDWR|os.O_TRUNC, 0644)
	errHandler(err)

	input, err := os.Open(basedir + url)
	errHandler(err)

	node, err := html.Parse(input)
	errHandler(err)

	input.Close()

	con := func(nd *html.Node) bool {
		return nd.Data == "h1"
	}

	firstNode := getNode(node, con)

	out.WriteString(makeHeading(level, title))

	// 添加章节开头的链接
	out.WriteString(genHyperTag(url, "", ""))
	ct := context{}
	out.WriteString(getNodeContent(firstNode, level+1, url, ct))

	outFile.WriteString(`\input{` + chapdir + id + "}\n")

	out.Close()
}

func getNodeContent(node *html.Node, level int, name string, con context) string {
	str := ""
	cnt := 0
	newCon := con.cols == 0

	for {
		if node == nil {
			return str
		}

		if newCon {
			con = context{}
		}

		if node.Type == html.ElementNode {
			tag := node.Data
			id := getAttr(node, "id")
			class := getAttr(node, "class")

			var prefix, appendix, end string
			var close, newline int

			cnt++

			if id != "" {
				str += genHyperTag(name, id, "")
			}

			switch tag {
			case "h1":
				node = node.NextSibling
				continue
			case "h2":
				str += makeHeading(level, escapeTexLite(getTitle(node.FirstChild)))
				node = node.NextSibling
				continue
			case "h3":
				str += makeHeading(level+1, escapeTexLite(getTitle(node.FirstChild)))
				node = node.NextSibling
				continue
			case "b", "strong":
				prefix = `\textbf{`
			case "i":
				prefix = `\textit{`
			case "em":
				prefix = `\emph{`
			case "u":
				prefix = `\uline{`
			case "strike":
				prefix = `\sout{`
			case "br":
				// 表格内禁用换行
				if con.cols == 0 {
					str += "\\\\\n"
				} else {
					str += "\\\\"
				}
				node = node.NextSibling
				continue
			case "span":
				switch class {
				case "summary":
					str += `\textbf{`
					close = 1
				case "remark":
					// 编者注类型
					str += `\footnote{`
					close = 1
				case "": // 没有class的span，常用于假名表中其他发音，直接显示内容
				case "popup":
				default:
					fmt.Println("Unknown span type ", class)
				}
			case "div":
				if id == "basic-modal-content" {
					node = node.NextSibling
					continue
				}

				switch class {
				case "sumbox", "note":
					title := "提示"
					nNode := node.FirstChild

					tnode := getNode(node, func(nd *html.Node) bool {
						return nd.Data == "span" && getAttr(nd, "class") == "summary"
					})

					if tnode != nil {
						title = getNodeStr(tnode)
						nNode = tnode.NextSibling
					}

					if nNode.Data == "br" {
						nNode = nNode.NextSibling
					}

					str += "\\begin{tkbasebox}%\n\\node[tkbox](box){%\n\\begin{tkinsidebox}%\n"
					str += getNodeContent(nNode, level, name, con)
					str += "%\n\\end{tkinsidebox}%\n};%\n\\tkboxheader{" + title + "}%\n\\end{tkbasebox}\n\n"

					node = node.NextSibling
					continue
				case "book-navigation":
					// 不解析每章开头的导航
					node = node.NextSibling
					continue
				default:
					fmt.Println("Unknown div type", class)
				}
			case "img":
				str += "\\begin{center}\\includegraphics[width=0.5\\textwidth]{" + getPic(getAttr(node, "src")) + "}\\end{center}"
			case "ul":
				if class == "menu" {
					// 跳过章节最底下练习的导航
					node = node.NextSibling
					continue
				}
				str += "\\begin{itemize}\n"
				end = "itemize"

			case "ol":
				str += "\\begin{enumerate}\n"
				end = "enumerate"
			case "li":
				str += "\\item "
				newline = 1
			case "p":
				if strings.Contains(getNodeStr(node), "作者：Tae Kim") {
					node = node.NextSibling
					continue
				}
				newline = 2
			case "font":
				if getAttr(node, "size") != "" {
					prefix = "\\small{"
				} else {
					fmt.Println("Font tag with unknown options", node)
				}
			case "center":
				str += "\\begin{center}\n"
				end = "center"

			case "table":
				subtable := getNode(node.FirstChild, func(nd *html.Node) bool {
					return nd.Data == "table" || nd.Data == "br"
				})
				// 仅在有子表格或换行的时候启用水平线
				con.hline = (subtable != nil)

				if class == "scale-to-page-width" {
					str += "\\resizebox{\\textwidth}{!}{"
					close = 1
				} else if con.cols == 0 {
					str += "\\begin{center}\n"
					appendix = "\\end{center}\n"
				}

				col := getTableColCount(node)
				borderAttr := getAttr(node, "border")
				border := borderAttr != "" && borderAttr != "0"

				str += "\\begin{tabular}{" + genTexTableHead(col, border) + "}\n"
				con.cols = col

				end = "tabular"
				newline = 1

				// todo: fix table tree
			case "caption":
				prefix = "\\multicolumn{" + strconv.Itoa(con.cols) + "}{c}{\\cellcolor{tablecaption}"
				appendix = " \\\\\n\\hline "
			case "tr":
				appendix = "\\\\\n"
				if con.hline {
					appendix += "\\hline"
				}
			case "td":
				prefix = "\\tabincell{c}{"
				if cnt < con.cols {
					appendix = " & "
				}
			case "th":
				colspan := getAttr(node, "colspan")
				if colspan != "" {
					prefix += "\\multicolumn{" + colspan + "}{c}{"
					appendix += "}"

					col, err := strconv.Atoi(colspan)
					errHandler(err)
					cnt += (col - 1)
				}
				prefix += "\\cellcolor{tableheader}\\textbf{"
				if cnt < con.cols {
					appendix += " & "
				}
			case "script", "nav":
				node = node.NextSibling
				continue
			case "a":
				if class == "playIcon" || strings.Contains(getNodeStr(node), "练习") {
					node = node.NextSibling
					continue
				}
				href := getAttr(node, "href")
				if href != "" {
					if strings.Contains(href, "http") {
						target := escapeTexLite(href)
						prefix = "\\href{" + target + "}{"
						appendix = `\linktarget{\footnote{\url{` + target + `}}}`
					} else {
						target := escapeInnerLink(strings.Replace(href, "#", "-", -1))
						prefix = "\\hyperlink{" + target + "}{"
						appendix = `\linktarget{ (P\pageref{` + target + `})}`
					}
				}
			case "sup":
				key := getNodeStr(node)
				// 查找带有 sup 的 remark
				knd := getNode(node.Parent.NextSibling, func(nd *html.Node) bool {
					if nd.Data == "span" && getAttr(nd, "class") == "remark" {
						return getNode(nd.FirstChild, func(cnd *html.Node) bool {
							return cnd.Data == "sup" && getNodeStr(cnd) == key
						}) != nil
					}
					return false
				})
				if knd != nil {
					str += `\footnote{` + getNodeRealStr(knd) + `}`
					knd.Data = "skip" // 跳过后面的解释

					node = node.NextSibling
					continue
				}
			case "skip":
				node = node.NextSibling
				continue
			case "iframe":
			case "audio":
			case "tbody":
				// continue
			default:
				fmt.Println("Unknown tag ", tag)
			}

			if prefix != "" {
				content := getNodeContent(node.FirstChild, level, name, con)
				str += prefix + content + "}" + appendix
				for i := 0; i < newline; i++ {
					str += "\n"
				}
				node = node.NextSibling
				continue
			}

			nstr := getNodeContent(node.FirstChild, level, name, con)
			str += nstr

			if end != "" {
				str += `\end{` + end + "}\n"
			}

			for i := 0; i < close; i++ {
				str += "}"
			}
			str += appendix
			for i := 0; i < newline; i++ {
				str += "\n"
			}
		} else if node.Type == html.TextNode {
			str += escapeTex(strings.TrimSpace(node.Data))
		}

		node = node.NextSibling
	}
}

// makeHeading 制作标题节
func makeHeading(level int, title string) string {
	levelCmd := []string{"chapter", "section", "subsection", "subsubsection"}
	cmd := levelCmd[level-1]
	return fmt.Sprintln(`\` + cmd + "{" + escapeTex(title) + "}")
}

// getTitle 获取标题节点的内容
func getTitle(node *html.Node) string {
	str := ""
	for {
		if node == nil {
			return str
		}

		if node.Type == html.TextNode {
			str += node.Data
		}
		str += getTitle(node.FirstChild)
		node = node.NextSibling
	}
}

// escapeTex 对文本进行转义
func escapeTex(text string) string {
	result := text

	result = strings.Replace(result, `\\`, `\textbackslash`, -1)

	result = strings.Replace(result, "{", "\\{", -1)
	result = strings.Replace(result, "}", "\\}", -1)
	result = strings.Replace(result, "%", "\\%", -1)
	result = strings.Replace(result, "#", "\\#", -1)
	result = strings.Replace(result, "、", "、{\\jpb}", -1)
	result = strings.Replace(result, "「", "{\\jpb}「", -1)
	result = strings.Replace(result, "」", "」{\\jpb}", -1)

	result = strings.Replace(result, "_", "\\_", -1)
	result = strings.Replace(result, "$", "\\$", -1)
	result = strings.Replace(result, "^", "\\^", -1)
	result = strings.Replace(result, "~", "\\~{}", -1)
	result = strings.Replace(result, "&", "\\&", -1)
	result = strings.Replace(result, ">", "{\\textgreater}", -1)
	result = strings.Replace(result, "<", "{\\textless}", -1)
	result = strings.Replace(result, "\\|", "{\\textbar}", -1)
	return result
}

// escapeInnerLink 转义内部链接的文本
func escapeInnerLink(text string) string {
	result := strings.Replace(text, "_", "-", -1)
	return escapeTexLite(result)
}

// escapeTexLite 仅转义必要的文本
func escapeTexLite(text string) string {
	result := text
	result = strings.Replace(result, "{", "\\{", -1)
	result = strings.Replace(result, "}", "\\}", -1)
	result = strings.Replace(result, "%", "\\%", -1)
	result = strings.Replace(result, "#", "\\#", -1)
	result = strings.Replace(result, "_", "\\_", -1)
	result = strings.Replace(result, "$", "\\$", -1)
	result = strings.Replace(result, "^", "\\^", -1)
	return result
}

// getNodeStr 获取节点下的文本
func getNodeStr(node *html.Node) string {
	if node != nil && node.FirstChild != nil {
		return node.FirstChild.Data
	}
	return ""
}

func getNodeRealStr(node *html.Node) string {
	if node != nil && node.FirstChild != nil {
		n := node.FirstChild
		for n != nil {
			if n.Type == html.TextNode {
				return n.Data
			}
			n = n.NextSibling
		}
	}
	return ""
}

// getPic 复制图像并处理
func getPic(org string) string {
	fName := chapdir + org
	convert := false

	if strings.HasSuffix(org, "gif") {
		convert = true
		fName = strings.TrimSuffix(fName, ".gif") + ".png"
	}

	checkDir(outdir + fName)

	input, err := os.Open(basedir + org)
	errHandler(err)

	output, err := os.OpenFile(outdir+fName, os.O_CREATE|os.O_RDWR|os.O_TRUNC, 0644)
	errHandler(err)

	if convert {
		img, err := gif.Decode(input)
		errHandler(err)

		err = png.Encode(output, img)
		errHandler(err)
	} else {
		_, err = io.Copy(output, input)
		errHandler(err)
	}

	input.Close()
	output.Close()

	return fName
}

// checkDir 用于检测文件所在目录是否存在
func checkDir(file string) {
	dir := filepath.Dir(file)

	_, err := os.Stat(dir)
	if err != nil && os.IsNotExist(err) {
		err = os.MkdirAll(dir, 0755)
		errHandler(err)
	}
}

// getTableColCount 用于获取表格的列数
func getTableColCount(node *html.Node) int {
	tdNode := getNode(node, func(n *html.Node) bool {
		return n.Data == "tr"
	})
	nd := tdNode.FirstChild
	count := 0

	for {
		if nd == nil {
			break
		}

		if nd.Data == "td" || nd.Data == "th" {
			col := getAttr(nd, "colspan")
			if col != "" {
				num, err := strconv.Atoi(col)
				errHandler(err)
				count += num
			} else {
				count++
			}
		}
		nd = nd.NextSibling
	}
	return count
}

// genTexTableHead 生成Tex用的表头文本
func genTexTableHead(count int, border bool) string {
	str := ""
	for i := 0; i < count; i++ {
		if border && i != 0 {
			str += "|"
		}
		str += "c"
	}
	return str
}

func genHyperTag(name string, id string, text string) string {
	target := ""
	if id == "" {
		target = escapeInnerLink(name)
	} else {
		target = escapeInnerLink(name + "-" + id)
	}
	return `\hypertarget{` + target + `}{\label{` + target + `}` + text + `}`
}
