from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os
SRC=r"C:/Users/Dev/AppData/Local/Temp/claude/D--Project-attendence/089dc38c-51a8-438a-9bc5-1ef4ba56151a/scratchpad/shots"
OUT=r"D:/Project/attendence/store_screenshots/framed"
B=r"C:/Windows/Fonts/segoeuib.ttf"; R=r"C:/Windows/Fonts/segoeui.ttf"
SHOTS=[('login','Sign in securely','Use your employee ID or phone number'),
       ('today','Check in with one tap','See your working hours live, all day'),
       ('form','Daily task report','Fill your department form in seconds'),
       ('attendance','Your attendance at a glance','Every day of the month, in one place'),
       ('leave','Apply for leave','Track balance and approvals instantly'),
       ('tickets','Raise IT tickets','Follow every request until it is resolved'),
       ('profile','Your profile','Light and dark themes built in')]
TOP,BOT=(47,107,255),(72,52,212)

def gradient(w,h):
    g=Image.new('RGB',(w,h)); d=ImageDraw.Draw(g)
    for y in range(h):
        t=y/h; d.line([(0,y),(w,y)],fill=tuple(int(TOP[i]+(BOT[i]-TOP[i])*t) for i in range(3)))
    # soft light blob for depth
    blob=Image.new('L',(w,h),0); ImageDraw.Draw(blob).ellipse((-w*.3,-h*.15,w*.9,h*.35),fill=60)
    blob=blob.filter(ImageFilter.GaussianBlur(w//8))
    return Image.composite(Image.new('RGB',(w,h),(255,255,255)),g,blob)

def rounded(im,r):
    m=Image.new('L',im.size,0); ImageDraw.Draw(m).rounded_rectangle((0,0,*im.size),r,fill=255)
    out=im.convert('RGBA'); out.putalpha(m); return out

def place(bg,shot,x,y,r):
    sh=Image.new('RGBA',bg.size,(0,0,0,0))
    ImageDraw.Draw(sh).rounded_rectangle((x+8,y+24,x+shot.width+8,y+shot.height+24),r,fill=(10,10,40,110))
    sh=sh.filter(ImageFilter.GaussianBlur(28))
    bg.alpha_composite(sh); bg.alpha_composite(rounded(shot,r),(x,y))

def text_c(d,cx,y,s,font,fill):
    w=d.textlength(s,font=font); d.text((cx-w/2,y),s,font=font,fill=fill)

def phone(name,title,sub,i):
    W,H=1080,1920
    bg=gradient(W,H).convert('RGBA'); d=ImageDraw.Draw(bg)
    text_c(d,W/2,110,title,ImageFont.truetype(B,76),'white')
    text_c(d,W/2,215,sub,ImageFont.truetype(R,40),(225,232,255))
    s=Image.open(f'{SRC}/raw_phone_{name}.png').convert('RGB')
    sh=int(H-340-40); sw=int(s.width*sh/s.height)
    s=s.resize((sw,sh),Image.LANCZOS)
    # phone bezel
    pad=14; frame=Image.new('RGB',(sw+2*pad,sh+2*pad),(18,20,28))
    frame.paste(s,(pad,pad)); fr=rounded(frame,64)
    s2=rounded(s,52); fr.alpha_composite(s2,(pad,pad))
    place(bg,fr,(W-fr.width)//2,340,64)
    bg.convert('RGB').save(f'{OUT}/phone/{i:02d}_{name}.png')

def tablet(name,title,sub,i):
    W,H=2560,1600
    bg=gradient(W,H).convert('RGBA'); d=ImageDraw.Draw(bg)
    text_c(d,W/2,80,title,ImageFont.truetype(B,96),'white')
    text_c(d,W/2,210,sub,ImageFont.truetype(R,50),(225,232,255))
    s=Image.open(f'{SRC}/raw_tab_{name}.png').convert('RGB')
    sh=H-330-70; sw=int(s.width*sh/s.height)
    s=s.resize((sw,sh),Image.LANCZOS)
    pad=18; frame=Image.new('RGB',(sw+2*pad,sh+2*pad),(18,20,28)); fr=rounded(frame,48)
    fr.alpha_composite(rounded(s,32),(pad,pad))
    place(bg,fr,(W-fr.width)//2,320,48)
    bg.convert('RGB').save(f'{OUT}/tablet/{i:02d}_{name}.png')

os.makedirs(OUT+'/phone',exist_ok=True); os.makedirs(OUT+'/tablet',exist_ok=True)
for i,(n,t,s) in enumerate(SHOTS,1): phone(n,t,s,i); tablet(n,t,s,i)
print('ok')
