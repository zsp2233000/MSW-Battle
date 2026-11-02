// Extends the existing guarded catalog fixture only for #49's overflow acceptance.
const fs = require('node:fs');
const readline = require('node:readline');
const {withTemporaryMonsterCsv,parseMonsterCsv,sha256}=require('./monster_catalog_csv_fixture.cjs');
const {createAcknowledgementBridge}=require('./monster_catalog_fixture_driver.cjs');
async function main(){
  const input=readline.createInterface({input:process.stdin});
  const request=createAcknowledgementBridge(input, m=>process.stdout.write(JSON.stringify(m)+'\n'));
  try {
    await request('stop',{stage:'before-install'});
    await withTemporaryMonsterCsv(async ({signal,...manifest})=>{
      const parsed=parseMonsterCsv(fs.readFileSync(manifest.csvPath));
      const variant=parsed.records.find(r=>r.MonsterId==='probe_tank_variant');
      for(let i=1;i<=14;i++) parsed.records.push({...variant,MonsterId:'probe_tank_'+String(i).padStart(2,'0'),MonsterName:'VariantTank '+i});
      const fixture=Buffer.from(parsed.bom+[parsed.header.join(','),...parsed.records.map(r=>parsed.header.map(k=>r[k]).join(','))].join('\n')+'\n');
      fs.writeFileSync(manifest.csvPath,fixture);
      if(!fs.readFileSync(manifest.csvPath).equals(fixture)) throw new Error('overflow fixture write mismatch');
      await request('editor-catalog-probe',{...manifest,overflowSha256:sha256(fixture)},{signal});
    },{
      variantStats:{MaxHp:650,AttackDamage:25,AttackIntervalSeconds:1.3,AttackRange:.8},
      lifecycle:{stop:details=>request('stop',details),refresh:details=>request('refresh',details),verifyRestored:details=>request('restored-probe',{sha256:details.originalSha256})},
      logger:message=>process.stdout.write(message+'\n'),
    });
    process.stdout.write('[VRF][EditorCatalogFixture] PASS\n');
  } finally {input.close();}
}
main().catch(error=>{console.error(error);process.exitCode=1;});
