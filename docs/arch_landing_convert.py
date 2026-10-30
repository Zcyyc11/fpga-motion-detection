import sys
from html4docx.h4d import HtmlToDocx

src, dst = sys.argv[1], sys.argv[2]
HtmlToDocx().parse_html_file(src, dst)
print("CONVERT_OK", dst)
