import time, torch, torch.nn as nn, math
torch.set_num_threads(4)

class Block(nn.Module):
    def __init__(s,d,h,f):
        super().__init__()
        s.n1=nn.LayerNorm(d); s.qkv=nn.Linear(d,3*d); s.proj=nn.Linear(d,d)
        s.n2=nn.LayerNorm(d); s.l1=nn.Linear(d,f); s.l2=nn.Linear(f,d); s.h=h; s.d=d
    def forward(s,x):
        B,T,D=x.shape
        q,k,v=s.qkv(s.n1(x)).split(D,dim=2)
        hd=D//s.h
        q=q.view(B,T,s.h,hd).transpose(1,2); k=k.view(B,T,s.h,hd).transpose(1,2); v=v.view(B,T,s.h,hd).transpose(1,2)
        y=torch.nn.functional.scaled_dot_product_attention(q,k,v,is_causal=True)
        x=x+s.proj(y.transpose(1,2).reshape(B,T,D))
        x=x+s.l2(torch.nn.functional.gelu(s.l1(s.n2(x))))
        return x

class M(nn.Module):
    def __init__(s,V,D,H,L,F,T):
        super().__init__()
        s.tok=nn.Embedding(V,D); s.pos=nn.Embedding(T,D)
        s.blocks=nn.ModuleList([Block(D,H,F) for _ in range(L)])
        s.ln=nn.LayerNorm(D); s.V=V
    def forward(s,idx):
        B,T=idx.shape
        x=s.tok(idx)+s.pos(torch.arange(T))
        for b in s.blocks: x=b(x)
        return torch.nn.functional.linear(s.ln(x),s.tok.weight)

for (V,D,H,L,F,T,B) in [(2400,128,4,4,512,192,24),(2800,160,4,4,640,192,24),(3200,192,6,5,768,256,16)]:
    m=M(V,D,H,L,F,T); n=sum(p.numel() for p in m.parameters())
    opt=torch.optim.AdamW(m.parameters(),lr=3e-4)
    x=torch.randint(0,V,(B,T))
    t0=time.time()
    for _ in range(3):
        logits=m(x)
        loss=torch.nn.functional.cross_entropy(logits.view(-1,V),x.view(-1))
        opt.zero_grad(); loss.backward(); opt.step()
    dt=(time.time()-t0)/3
    print(f"V={V} D={D} L={L} F={F} T={T} B={B}  params={n/1e6:.2f}M  {dt:.2f}s/step -> 3000 steps = {dt*3000/60:.0f} min")
