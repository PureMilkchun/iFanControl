// Browser regression for the actual dashboard drawing functions; synthetic data only.
const fs = require('fs'), path = require('path'), assert = require('assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const source = fs.readFileSync(process.argv[2] || path.resolve(__dirname, '../../ifan-stats/app.js'), 'utf8');
const output = path.resolve(process.argv[3] || path.join(__dirname, '../packaging/pkg/output/stats-pie'));
const expectBug = process.argv.includes('--expect-bug');
fs.mkdirSync(output, {recursive: true});
const start = source.indexOf('const PIE_PALETTE_LIGHT');
const end = source.indexOf('function getFeedbackDoneSet()', start);
assert(start >= 0 && end > start);
const colors = source.slice(source.indexOf('function getChartColors()'), source.indexOf('function setAuthed('));
const drawing = colors + source.slice(start, end) + '\nwindow.pieFixture={render:renderVersionPieChart,draw:drawPie,palette:getPiePalette};';
const cases = [
  ['reported', [47, 45, 90, 1, 7, 1, 1]],
  ['near-skip-boundary', [313, 1]],
  ['below-gap-width', [125, 1]],
  ['above-gap-width', [124, 1]],
  ['single-version', [192]],
  ['zero-and-tiny', [1000, 0, 1]],
  ['empty', []],
];
const styles = fs.readFileSync(path.resolve(__dirname, '../../ifan-stats/styles.css'), 'utf8');
(async () => {
  const browser = await chromium.launch({headless:true, executablePath:process.env.PLAYWRIGHT_BROWSER || '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'});
  const records=[];
  for (const theme of ['light', 'dark']) {
    const page=await browser.newPage({viewport:{width:1280,height:800},deviceScaleFactor:2});
    for (const [name, counts] of cases) {
      await page.setContent(`<html data-theme="${theme}"><head><style>${styles}</style></head><body><main class="app-shell"><div class="version-split"><section class="panel version-panel"><h2>当前版本分布</h2><table><thead><tr><th>版本 (Build)</th><th>用户数</th></tr></thead><tbody>${counts.map((n,i)=>`<tr><td>fixture-${i}</td><td>${n}</td></tr>`).join('')}</tbody></table></section><section class="panel version-panel"><h2>版本占比</h2><div class="pie-wrap"><canvas id="versionPieChart"></canvas><div id="pieLegend" class="pie-legend"></div></div></section></div></main></body></html>`);
      await page.addScriptTag({content:drawing});
      const result=await page.evaluate(counts=>{
        const rows=counts.map((count,i)=>({version:'fixture-'+i,count}));window.pieFixture.render(rows);
        const canvas=document.getElementById('versionPieChart'),ctx=canvas.getContext('2d'),total=counts.reduce((a,b)=>a+b,0),palette=window.pieFixture.palette();
        const samples=[];let angle=-Math.PI/2;
        for(let i=0;i<counts.length;i++){
          const sweep=counts[i]/total*Math.PI*2;
          if(sweep>=0.02){const mid=angle+sweep/2;const x=Math.round((120+103*Math.cos(mid))*devicePixelRatio),y=Math.round((120+103*Math.sin(mid))*devicePixelRatio);samples.push({index:i,actual:[...ctx.getImageData(x,y,1,1).data],expected:palette[i%palette.length]});}
          angle+=sweep;
        }
        return {total,samples,legend:document.getElementById('pieLegend').textContent};
      },counts);
      let mismatches=0;
      for(const s of result.samples){const expected=s.expected.match(/\w\w/g).map(v=>parseInt(v,16));if(s.actual[3]!==255||expected.some((v,i)=>Math.abs(v-s.actual[i])>1))mismatches++;}
      if(expectBug && name==='reported')assert(mismatches>0,'must reproduce the actual visual defect');
      else if(!expectBug)assert.equal(mismatches,0,theme+'/'+name+' has an overwritten/missing rendered sector');
      records.push({theme,name,total:result.total,mismatches});
      if(name==='reported'){
        await page.locator('.version-split').screenshot({path:path.join(output,theme+'-desktop.png')});
        if(!expectBug){
          const box=await page.locator('#versionPieChart').boundingBox();
          // Hover the dominant segment in the real event handler, then leave.
          const mid=-Math.PI/2+(47+45+90/2)/192*Math.PI*2;
          await page.mouse.move(box.x+120+90*Math.cos(mid),box.y+120+90*Math.sin(mid));
          assert.equal(await page.locator('.pie-legend-item').nth(2).evaluate(el=>el.style.fontWeight),'600');
          await page.locator('.version-split').screenshot({path:path.join(output,theme+'-hover.png')});
          await page.mouse.move(0,0);assert.equal(await page.locator('.pie-legend-item').nth(2).evaluate(el=>el.style.fontWeight),'');
          await page.setViewportSize({width:390,height:844});await page.locator('#versionPieChart').scrollIntoViewIfNeeded();
          assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
          await page.screenshot({path:path.join(output,theme+'-mobile.png')});
          await page.setViewportSize({width:1280,height:800});
        }
      }
    }
    await page.close();
  }
  fs.writeFileSync(path.join(output,'verification.json'),JSON.stringify({expectBug,cases:records,synthetic:true},null,2));
  await browser.close();console.log(`PASS: ${expectBug?'original bug reproduced':'all sectors retain correct rendered colors'}, ${records.length} real browser cases; no network/auth/database access.`);
})().catch(e=>{console.error(e);process.exit(1)});
