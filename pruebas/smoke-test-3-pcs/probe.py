import sys, urllib.request, urllib.error
for url in sys.argv[1:]:
    try:
        r = urllib.request.urlopen(url, timeout=8)
        print(url, r.status)
    except urllib.error.HTTPError as e:
        print(url, "HTTP", e.code)
    except Exception as e:
        print(url, "ERR", type(e).__name__, e)
