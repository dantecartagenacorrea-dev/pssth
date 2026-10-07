import re,sys
s=open(sys.argv[1],encoding='utf-8').read()
for m in re.finditer(r'(?:content-desc|text)="([^"]+)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',s):
    print(m.group(1)[:70].replace('&#10;',' | '), (int(m.group(2))+int(m.group(4)))//2, (int(m.group(3))+int(m.group(5)))//2)
