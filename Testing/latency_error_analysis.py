import json, os, re, statistics
from collections import defaultdict

RESULTS_DIR = '/home/dwan13/muBench/Testing/results/auto_runs/randomized_campaigns/'
summary = []

for fname in sorted(os.listdir(RESULTS_DIR)):
    if not fname.endswith('.json'):
        continue
    fpath = os.path.join(RESULTS_DIR, fname)
    m = re.search(r'order(\d+)_(C\d+)_([^_]+)_(\d+)vus', fname)
    if not m:
        continue
    order, control, scenario, vus = m.group(1), m.group(2), m.group(3), m.group(4)
    latencies = []
    errors = defaultdict(int)
    with open(fpath) as fp:
        for line in fp:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except:
                continue
            if obj.get('type') != 'Point':
                continue
            data = obj.get('data', {})
            tags = data.get('tags', {})
            url = tags.get('name', '') or tags.get('url', '')
            status = tags.get('status', '')
            metric = obj.get('metric', '')
            if metric == 'http_req_duration':
                latencies.append(data.get('value', 0))
            if metric == 'http_reqs' and status and status != '200':
                errors[status] += 1
    summary.append({
        'order': int(order), 'control': control, 'scenario': scenario, 'vus': int(vus),
        'latencies': latencies, 'errors': dict(errors)
    })

print('{:>5} {:>4} {:>16} {:>4} | {:>8} {:>8} {:>8} | {:>20}'.format('Ord','Ctrl','Scenario','VUs','AvgLat','P95Lat','Errs','TopErrs'))
print('-'*80)
for s in summary:
    if s['latencies']:
        avg = round(statistics.mean(s['latencies']),2)
        try:
            p95 = round(statistics.quantiles(s['latencies'],n=100)[94],2)
        except:
            p95 = 0
    else:
        avg = p95 = 0
    top_err = max(s['errors'].items(), key=lambda x: x[1])[0] if s['errors'] else '-'
    print('{:>5} {:>4} {:>16} {:>4} | {:>8} {:>8} {:>8} | {:>20}'.format(
        s['order'],s['control'],s['scenario'],s['vus'],avg,p95,sum(s['errors'].values()),top_err))

print('\nTOTALES POR CONTROL:')
by_ctrl = defaultdict(lambda: {'latencies': [], 'errors': defaultdict(int)})
for s in summary:
    by_ctrl[s['control']]['latencies'].extend(s['latencies'])
    for k,v in s['errors'].items():
        by_ctrl[s['control']]['errors'][k] += v
for ctrl in sorted(by_ctrl.keys()):
    lats = by_ctrl[ctrl]['latencies']
    avg = round(statistics.mean(lats),2) if lats else 0
    try:
        p95 = round(statistics.quantiles(lats,n=100)[94],2) if lats else 0
    except:
        p95 = 0
    errc = sum(by_ctrl[ctrl]['errors'].values())
    print('  {}: avg_lat={}ms p95_lat={}ms total_errs={}'.format(ctrl, avg, p95, errc))
