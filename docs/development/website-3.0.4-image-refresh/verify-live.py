from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
from pathlib import Path
import json
import re
import subprocess
import time

out = Path(__file__).resolve().parent
load = lambda name: json.loads((out / name).read_text())
previous = load('previous-deployment.json')['result']
accepted = load('deploy-api-response.json')['result']
expected = load('deploy-manifest.json')
stage = load('staging-summary.json')
cloud_base = 'https://api.cloudflare.com/client/v4/accounts/6af3ba3f14eda02e1dcf2c31dabe1300/pages/projects/ifan'
config = (Path.home() / 'Library/Preferences/.wrangler/config/default.toml').read_text()
token = re.search(r'^oauth_token\s*=\s*"([^"]+)"', config, re.M)[1]

def api(path=''):
    response = subprocess.check_output(['curl', '-fsS', '--retry', '2', '--max-time', '20', '--config', '-', cloud_base + path],
        input=f'header = "Authorization: Bearer {token}"\n'.encode())
    result = json.loads(response)
    assert result['success']
    return result['result']

for _ in range(16):
    current = api('/deployments/' + accepted['id'])
    status = current['latest_stage']['status']
    if status == 'success' and api()['canonical_deployment']['id'] == current['id']:
        break
    assert status not in ('failure', 'canceled'), status
    time.sleep(2)
else:
    raise RuntimeError('Stable deployment has not become canonical')

assert current['files'] == expected
assert set(previous['files']) <= set(expected)
assert {n for n,v in expected.items() if previous['files'].get(n) != v} == set(stage['changed_existing_assets'] + stage['added_assets'])
for key in ('compatibility_date','compatibility_flags','usage_model','uses_functions','d1_databases','r2_buckets','env_vars'):
    assert current.get(key) == previous.get(key), key
assert api()['deployment_configs'] == load('project-before.json')['result']['deployment_configs']
print('PASS: stable 95 is canonical and protected asset hashes and bindings match the plan', flush=True)

site = out / 'site'
stable = load('site/update-manifest-pkg.json')
restore = load('site/update-manifest-stable-restore.json')
legacy = load('site/update-manifest.json')
restore_package = restore['assets']['macos_arm64_pkg_url'].rsplit('/',1)[-1]
legacy_zip = legacy['assets']['macos_arm64_zip_url'].split('?',1)[0].rsplit('/',1)[-1]
pkg = (out/'iFanControl-3.0.4.pkg').read_bytes()
pkg_sha = sha256(pkg).hexdigest()

def download(url, path, headers=None, user_agent=None):
    args = ['curl','-fsSL','--retry','2','--retry-all-errors','--max-time','90','--connect-timeout','10','-o',str(path)]
    if headers:
        args.extend(['-D',str(headers)])
    if user_agent:
        args.extend(['-A',user_agent])
    subprocess.run(args + [url], check=True)
    return path.read_bytes()

def verify_origin(origin, label):
    dest = out / 'online' / label
    dest.mkdir(parents=True, exist_ok=True)
    for name in ('update-manifest-pkg.json','update-manifest-beta.json','update-manifest-stable-restore.json','timeline.json'):
        headers = dest / (name+'.headers')
        data = download(origin + '/' + name, dest / name, headers)
        assert data == (site / name).read_bytes(), (origin, name)
        if name.startswith('update-manifest'):
            fields=headers.read_text().lower()
            assert 'cache-control: no-store' in fields and 'content-type: application/json' in fields, (origin, name)
    homepage = download(origin+'/', dest/'index.html')
    candidate_homepage = (site/'index.html').read_bytes()
    if homepage != candidate_homepage and label == 'official':
        # The custom-domain Cloudflare edge adds these two observed verification
        # snippets. Require their exact shape and compare every remaining byte.
        html = homepage.decode()
        link = re.search(r'(<a href="https://ifancontrol\.puremilkchun\.top/cdn-cgi/content\?id=[A-Za-z0-9_.-]+" aria-hidden="true" rel="nofollow noopener" style="display: none !important; visibility: hidden !important"></a>)', html)
        script = re.search(r'(<script>\(function\(\)\{function c\(\)\{var b=a\.contentDocument.*?</script>)(?=</body>)', html)
        assert link and script, 'Unexpected official homepage change'
        normalized_script = re.sub(r"r:'[a-f0-9]+'", "r:'RAY'", re.sub(r"t:'[A-Za-z0-9=]+'", "t:'TIME'", re.sub(r"\?ray=[a-f0-9]+", '?ray=RAY', script[1])))
        assert normalized_script == (out/'cloudflare-edge-script.template').read_text()
        homepage = html.replace(link[1], '', 1).replace(script[1], '', 1).encode()
    assert homepage == candidate_homepage, (origin, 'index.html')
    for image_path in stage['refreshed_website_images']:
        filename = image_path.lstrip('/')
        target = dest/filename
        target.parent.mkdir(parents=True, exist_ok=True)
        data = download(origin+image_path, target)
        assert data == (site/filename).read_bytes(), (origin, image_path)
    for name in ('iFanControl-macOS.pkg','iFanControl-3.0.4-95.pkg'):
        assert download(origin+'/'+name+'?build=95',dest/name)==pkg, (origin, name)
    restored = download(origin+'/'+restore_package, dest/restore_package)
    assert sha256(restored).hexdigest() == restore['assets']['pkg_sha256']
    heads = subprocess.check_output(['curl','-fsSI','--retry','2','--max-time','25',origin+'/download'],text=True)
    assert re.search(r'(?im)^location: https?://[^\s]+/iFanControl-macOS.pkg\?build=95\s*$',heads), (origin, heads)
    subprocess.run([str(out/'check-live'),str(dest)],check=True)
    subprocess.run([str(out/'check-restore'),str(dest)],check=True)
    for key,ua,version in (('mac14','iFanControl/50 CFNetwork/1 Darwin/23.6.0',0),
                           ('mac15','iFanControl/50 CFNetwork/3826 Darwin/24.5.0',52),
                           ('mac26','iFanControl/50 CFNetwork/1 Darwin/25.1.0',52),
                           ('unknown','unknown-client',0)):
        data = download(origin+'/update-manifest.json',dest/f'legacy-{key}.json',user_agent=ua)
        assert json.loads(data)['latest_build']==version, (origin,key)
        assert (data == (site/'update-manifest.json').read_bytes()) if version else json.loads(data)['assets'] is None
    if label=='pages':
        for name in (legacy_zip, 'iFanControl-macOS.zip'):
            data=download(origin+'/'+name,dest/name)
            assert sha256(data).hexdigest()==legacy['assets']['sha256']
    return {'origin':origin,'stable_build':95,'beta_feed_build':95,'beta_feed_channel':'stable','download_build':95,
            'package_sha256':pkg_sha,'stable_restore_build':95,'legacy_protection_verified':True}

def verify_github():
    info = load('github-release.json')
    assert info['tagName']=='v3.0.4' and not info['isPrerelease'] and not info['isDraft']
    assert '主菜单' in info['body']
    latest = subprocess.check_output(['gh','api','repos/PureMilkchun/iFanControl/releases/latest','--jq','.tag_name'],text=True).strip()
    assert latest=='v3.0.4', latest
    dest=out/'github-online'
    dest.mkdir(parents=True,exist_ok=True)
    subprocess.run(['gh','release','download','v3.0.4','--repo','PureMilkchun/iFanControl','--dir',str(dest),'--pattern','iFanControl-3.0.4.pkg*','--clobber'],check=True)
    assert (dest/'iFanControl-3.0.4.pkg').read_bytes()==pkg
    assert (dest/'iFanControl-3.0.4.pkg.sha256').read_bytes()==(out/'iFanControl-3.0.4.pkg.sha256').read_bytes()
    return info

with ThreadPoolExecutor(max_workers=3) as pool:
    page_result=pool.submit(verify_origin,'https://ifan-59w.pages.dev','pages')
    official_result=pool.submit(verify_origin,'https://ifancontrol.puremilkchun.top','official')
    github_result=pool.submit(verify_github)
    origins=[page_result.result(),official_result.result()]
    github=github_result.result()
report = {**stage, **load('promotion.json'), 'deployment':current['id'], 'deployed_at':current['created_on'],
          'github_release':github['url'], 'github_published_at':github['publishedAt'], 'source_tag':'v3.0.4',
          'origins':origins,'legacy_zip_hashes_preserved':True,'actual_installation_performed':False,
          'github_attachments_match_package':True,'runtime_bindings_preserved':True,
          'timeline_visually_verified_on_desktop_and_mobile':True, 'refreshed_website_images_verified':True,
          'website_visual_review':load('website-visual-review-final.json'),
          'custom_domain_edge_insertion':'Known Cloudflare verification snippets matched exact normalized template; all remaining homepage bytes identical to staged source'}
(out/'publication.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(f"Verified stable 95 on both update origins and GitHub Latest. Public PKG SHA256: {pkg_sha}")
