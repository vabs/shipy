"""Star-goal calibration (dev tool).

Reads one or more balance CSVs (tests/balance.gd, ideally >= 12 seeds, all three modes) and prints a
GOALS table for tools/gen_content.gd:
  goal 1: rating just under the passive mean (passive passes ~80%; floor 30 unless the passive mean is below 40),
  goal 2: ~80% pass for human play, ~10% for passive,
  goal 3: ~85% pass for the active bot, ~30% for human, ~0% for passive,
choosing rating / profit / served / no_lost_guests per level for variety.
Usage: python3 tests/goals.py 'tests/out/balance*.csv'
"""
import csv, glob, collections, sys, math
pattern = sys.argv[1] if len(sys.argv)>1 else 'tests/out/balance.csv'
rows=[]
for f in glob.glob(pattern):
    rows+=list(csv.DictReader(open(f)))
order=['med_%d'%i for i in range(1,7)]+['arctic_%d'%i for i in range(1,7)]+['underworld_%d'%i for i in range(1,7)]
data=collections.defaultdict(lambda: collections.defaultdict(list))
for r in rows:
    data[r['level']][r['mode']].append(dict(rating=float(r['rating']),profit=float(r['profit']),served=float(r['served']),lost=float(r['lost'])))
def passes(runs, goal):
    t,v=goal
    if t=='rating': return sum(1 for x in runs if x['rating']>=v)/len(runs)
    if t=='profit': return sum(1 for x in runs if x['profit']>=v)/len(runs)
    if t=='served': return sum(1 for x in runs if x['served']>=v)/len(runs)
    if t=='no_lost_guests': return sum(1 for x in runs if x['lost']==0)/len(runs)
def cands(runs_all, t):
    if t=='no_lost_guests': return [(t,0)]
    key={'rating':'rating','profit':'profit','served':'served'}[t]
    step={'rating':1,'profit':50,'served':10}[t]
    vals=sorted(set(int(round(x[key]/step)*step) for m in runs_all for x in m))
    # add midpoints
    return [(t,v) for v in vals]
def score(pp,ph,pa,target):
    # target = (p_passive, p_human, p_active)
    return abs(ph-target[1])*1.0+abs(pa-target[2])*1.0+abs(pp-target[0])*1.2
def best(level, types, target, avoid=()):
    P=data[level]['passive'];H=data[level]['human'];A=data[level]['active']
    res=[]
    for t in types:
        for g in cands([P,H,A],t):
            s=score(passes(P,g),passes(H,g),passes(A,g),target)
            res.append((s,g))
    res.sort(key=lambda z:z[0])
    return res
def pick(level, types, target, prefer_order):
    res=best(level,types,target)
    top=res[0][0]
    # best per type
    per={}
    for s,g in res:
        if g[0] not in per: per[g[0]]=(s,g)
    # prefer variety: choose first type in prefer_order whose score is within 0.18 of the best
    for t in prefer_order:
        if t in per and per[t][0] <= top+0.18:
            return per[t][1], per[t][0]
    return res[0][1], res[0][0]
out=[]
alls={'p':0,'h':0,'a':0}
for i,lv in enumerate(order):
    P=data[lv]['passive'];H=data[lv]['human'];A=data[lv]['active']
    if not P: continue
    # goal 1: rating just under the passive mean: pass_passive ~ 0.8
    g1=min(best(lv,['rating'],(0.8,1.0,1.0)),key=lambda z:z[0])[1]
    t2_pref=[['profit','served','rating','no_lost_guests'],['served','profit','rating','no_lost_guests'],['rating','profit','served']][i%3]
    g2,s2=pick(lv,['rating','profit','served','no_lost_guests'],(0.12,0.8,0.97),t2_pref)
    t3_pref=[['no_lost_guests','rating','profit','served'],['rating','no_lost_guests','served','profit'],['served','rating','profit','no_lost_guests']][i%3]
    cand3=[t for t in ['rating','profit','served','no_lost_guests'] if t!=g2[0]]
    g3,s3=pick(lv,cand3,(0.02,0.3,0.85),t3_pref)
    if g1[1] < 30 and sum(x['rating'] for x in P)/len(P) >= 40: g1=('rating',30)
    if lv=='med_1': g1,g2,g3=('rating',70),('served',45),('no_lost_guests',0)
    goals=[g1,g2,g3]
    exp={k:sum(passes(d,g) for g in goals) for k,d in (('p',P),('h',H),('a',A))}
    for k in exp: alls[k]+=exp[k]
    print("%-13s goals %s | exp stars passive %.2f human %.2f active %.2f | ratings P %.1f H %.1f A %.1f"%(lv,goals,exp['p'],exp['h'],exp['a'],sum(x['rating'] for x in P)/len(P),sum(x['rating'] for x in H)/len(H),sum(x['rating'] for x in A)/len(A)))
    out.append(goals)
n=len(out)
print("mean expected stars: passive %.2f human %.2f active %.2f"%(alls['p']/n,alls['h']/n,alls['a']/n))
print("GOALS = [")
for g in out:
    print("\t[%s],"%", ".join('["%s", %d]'%(t,v) for t,v in g))
print("]")
