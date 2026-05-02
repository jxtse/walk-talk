from playwright.sync_api import sync_playwright
from pathlib import Path

OUT = Path(__file__).parent

with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome")
    ctx = browser.new_context(viewport={"width": 1500, "height": 900},
                              device_scale_factor=2)
    page = ctx.new_page()
    page.goto("http://127.0.0.1:8788/", wait_until="domcontentloaded")
    page.wait_for_timeout(1500)

    # full page first
    page.screenshot(path=str(OUT / "00-full.png"), full_page=False)

    # locate phone bbox
    phone = page.locator(".phone")
    box = phone.bounding_box()

    def shot_phone(name):
        page.screenshot(path=str(OUT / name), clip=box)

    # s1
    shot_phone("s1.png")
    # s2 via jump button
    page.click("button[data-jump='s2']")
    page.wait_for_timeout(700)
    shot_phone("s2.png")
    # s3
    page.click("button[data-jump='s3']")
    page.wait_for_timeout(700)
    shot_phone("s3.png")
    # s4
    page.click("button[data-jump='s4']")
    page.wait_for_timeout(700)
    shot_phone("s4.png")
    # s4 with drawer open
    page.evaluate("document.getElementById('dialog-drawer').classList.add('open')")
    page.evaluate("""
      const d = document.getElementById('dialog');
      ['你好呀','我们去哪走','左边那个咖啡店看起来不错','好，那走过去看看'].forEach((t,i)=>{
        const b=document.createElement('div');
        b.className = 'bubble ' + (i%2 ? 'user' : 'ai');
        b.textContent = t; d.appendChild(b);
      });
    """)
    page.wait_for_timeout(400)
    shot_phone("s4-drawer.png")
    # s5
    page.click("button[data-jump='s5']")
    page.wait_for_timeout(700)
    shot_phone("s5.png")
    # s6
    page.click("button[data-jump='s6']")
    page.wait_for_timeout(700)
    shot_phone("s6.png")
    # s7
    page.click("button[data-jump='s7']")
    page.wait_for_timeout(700)
    shot_phone("s7.png")

    browser.close()
print("done")
