import { StatementStrings, stringsFor } from './statements.i18n';
import { Lang, StatementView } from './statements.types';

const BRAND = '#E0611E';
const BRAND_SOFT = '#FFF1E8';
const INK = '#1F2430';
const MUTED = '#6B7280';
const LINE = '#E5E7EB';
const DANGER = '#C0392B';
const OK = '#1E8E5A';

/** Escapes text for HTML element content and quoted attributes. */
export function esc(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function formatKes(amount: number): string {
  const rounded = Math.round(amount * 100) / 100;
  const hasCents = Math.abs(rounded - Math.round(rounded)) > 0.004;
  return `KES ${rounded.toLocaleString('en-KE', {
    minimumFractionDigits: hasCents ? 2 : 0,
    maximumFractionDigits: 2,
  })}`;
}

export function formatDate(date: Date | null | undefined, lang: Lang): string {
  if (!date) return '';
  try {
    return new Intl.DateTimeFormat(lang === 'sw' ? 'sw-KE' : 'en-GB', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
      timeZone: 'Africa/Nairobi',
    }).format(date);
  } catch {
    return date.toISOString().slice(0, 10);
  }
}

/** The message a shop sends along with the link. */
export function shareMessage(view: StatementView, url: string, lang: Lang): string {
  const t = stringsFor(lang);
  const first = view.debtor.name.trim().split(/\s+/)[0] || view.debtor.name;
  const note = view.message ? `\n\n${view.message}` : '';
  return t.shareLine(first, view.business.name, formatKes(view.outstanding), url) + note;
}

export interface PageOptions {
  lang: Lang;
  token: string;
  nonce: string;
  appDownloadPath: string;
}

const CSS = `
*{box-sizing:border-box}
body{margin:0;background:#F6F7F9;color:${INK};font:16px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;-webkit-text-size-adjust:100%}
.wrap{max-width:560px;margin:0 auto;padding:16px 16px 40px}
.top{display:flex;align-items:center;justify-content:space-between;gap:12px;margin:4px 0 14px}
.shop{display:flex;align-items:center;gap:10px;min-width:0}
.shop img{width:40px;height:40px;border-radius:10px;object-fit:cover}
.shop b{font-size:17px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.lang{font-size:13px;color:${BRAND};text-decoration:none;font-weight:600;border:1px solid ${BRAND};border-radius:999px;padding:4px 10px;white-space:nowrap}
.hero{background:#fff;border-radius:18px;padding:20px;border:1px solid ${LINE};box-shadow:0 1px 2px rgba(0,0,0,.04)}
.hero small{color:${MUTED};display:block}
.owed{font-size:34px;font-weight:800;letter-spacing:-.5px;margin:2px 0 2px}
.owed.clear{color:${OK}}
.pill{display:inline-block;background:#FDECEA;color:${DANGER};border-radius:999px;padding:3px 10px;font-size:13px;font-weight:700;margin-top:6px}
.note{margin-top:12px;padding:10px 12px;background:${BRAND_SOFT};border-radius:10px;font-size:15px}
h2{font-size:13px;letter-spacing:.06em;text-transform:uppercase;color:${MUTED};margin:22px 4px 8px}
.card{background:#fff;border:1px solid ${LINE};border-radius:14px;padding:14px;margin-bottom:10px}
.row{display:flex;justify-content:space-between;gap:12px}
.row .l{min-width:0}
.ref{font-weight:700}
.sub{color:${MUTED};font-size:13px}
.amt{font-weight:800;white-space:nowrap}
.late{color:${DANGER};font-weight:700}
.pay{white-space:pre-wrap}
.btns{display:grid;gap:10px;margin-top:14px}
button,.btn{appearance:none;border:0;border-radius:12px;padding:14px 16px;font-size:16px;font-weight:700;cursor:pointer;text-align:center;text-decoration:none;display:block}
.primary{background:${BRAND};color:#fff}
.ghost{background:#fff;color:${INK};border:1px solid ${LINE}}
form{display:none;margin-top:12px}
form.open{display:block}
label{display:block;font-size:13px;color:${MUTED};margin:10px 0 4px}
input{width:100%;font-size:16px;padding:12px;border:1px solid ${LINE};border-radius:10px;background:#fff;color:${INK}}
.help{font-size:12px;color:${MUTED};margin-top:4px}
.msg{margin-top:10px;font-size:15px;font-weight:600}
.msg.ok{color:${OK}} .msg.bad{color:${DANGER}}
.join{background:${INK};color:#fff;border-radius:16px;padding:18px;margin-top:26px}
.join h3{margin:0 0 6px;font-size:18px}
.join p{margin:0 0 14px;color:#D1D5DB;font-size:15px}
.join .btn{background:${BRAND};color:#fff}
.foot{text-align:center;color:${MUTED};font-size:12px;margin-top:22px}
`;

const SCRIPT = `
(function(){
  var root=document.getElementById('claims');
  if(!root)return;
  var token=root.getAttribute('data-token');
  function show(form){
    var forms=root.querySelectorAll('form');
    for(var i=0;i<forms.length;i++){forms[i].className=forms[i]===form&&form.className!=='open'?'open':''}
  }
  root.querySelectorAll('[data-open]').forEach(function(b){
    b.addEventListener('click',function(){show(document.getElementById(b.getAttribute('data-open')))});
  });
  root.querySelectorAll('form').forEach(function(form){
    form.addEventListener('submit',function(e){
      e.preventDefault();
      var msg=form.querySelector('.msg');
      var btn=form.querySelector('button[type=submit]');
      var body={kind:form.getAttribute('data-kind')};
      new FormData(form).forEach(function(v,k){if(String(v).trim()!=='')body[k]=String(v).trim()});
      btn.disabled=true;var label=btn.textContent;btn.textContent=root.getAttribute('data-sending');
      fetch('/s/'+encodeURIComponent(token)+'/claims',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)})
        .then(function(r){return r.json().then(function(j){return {ok:r.ok,j:j}})})
        .then(function(res){
          msg.className='msg '+(res.ok?'ok':'bad');
          var text=res.j&&res.j.message;
          if(Array.isArray(text))text=text.join(' ');
          msg.textContent=text||root.getAttribute(res.ok?'data-thanks':'data-error');
          if(res.ok){form.querySelectorAll('input').forEach(function(i){i.disabled=true});btn.style.display='none'}
          else{btn.disabled=false;btn.textContent=label}
        })
        .catch(function(){msg.className='msg bad';msg.textContent=root.getAttribute('data-error');btn.disabled=false;btn.textContent=label});
    });
  });
})();
`;

function itemCard(item: StatementView['items'][number], t: StatementStrings, lang: Lang): string {
  const late = item.overdueDays > 0;
  return `<div class="card">
  <div class="row">
    <div class="l">
      <div class="ref">${esc(item.reference)}</div>
      <div class="sub">${esc(formatDate(item.date, lang))}${item.description ? ` · ${esc(item.description)}` : ''}</div>
      ${item.dueDate ? `<div class="sub ${late ? 'late' : ''}">${late ? esc(t.overdueBy(item.overdueDays)) : `${esc(t.due)} ${esc(formatDate(item.dueDate, lang))}`}</div>` : ''}
    </div>
    <div style="text-align:right">
      <div class="amt">${esc(formatKes(item.outstanding))}</div>
      ${item.paid > 0 ? `<div class="sub">${esc(t.paidSoFar)} ${esc(formatKes(item.paid))} / ${esc(formatKes(item.original))}</div>` : ''}
    </div>
  </div>
</div>`;
}

export function renderStatementPage(view: StatementView, options: PageOptions): string {
  const { lang, token, nonce } = options;
  const t = stringsFor(lang);
  const other: Lang = lang === 'sw' ? 'en' : 'sw';
  const owed = view.outstanding > 0;
  const base = `/s/${encodeURIComponent(token)}`;

  const items = view.items.map((item) => itemCard(item, t, lang)).join('');
  const payments = view.payments
    .map(
      (p) => `<div class="card"><div class="row"><div class="l"><div class="ref">${esc(formatDate(p.date, lang))}</div>
      <div class="sub">${esc((t.method as Record<string, string>)[p.method] ?? p.method)}${p.reference ? ` · ${esc(p.reference)}` : ''}</div></div>
      <div class="amt" style="color:${OK}">${esc(formatKes(p.amount))}</div></div></div>`,
    )
    .join('');

  const claims = owed
    ? `<div id="claims" data-token="${esc(token)}" data-sending="${esc(t.sending)}" data-thanks="${esc(t.thanks(view.business.name))}" data-error="${esc(t.somethingWrong)}">
  <div class="btns">
    <button class="primary" type="button" data-open="paid">${esc(t.paidAlready)}</button>
    <button class="ghost" type="button" data-open="promise">${esc(t.promise)}</button>
  </div>
  <form id="paid" data-kind="PAID" autocomplete="off">
    <label for="mpesaCode">${esc(t.mpesaCode)}</label>
    <input id="mpesaCode" name="mpesaCode" maxlength="12" autocapitalize="characters" required>
    <div class="help">${esc(t.codeHelp)}</div>
    <label for="amount">${esc(t.amountKes)}</label>
    <input id="amount" name="amount" type="number" inputmode="decimal" min="1" step="0.01" required value="${esc(Math.round(view.outstanding))}">
    <label for="payerName">${esc(t.yourName)}</label>
    <input id="payerName" name="payerName" maxlength="80">
    <div class="btns"><button class="primary" type="submit">${esc(t.send)}</button></div>
    <div class="msg" role="status"></div>
  </form>
  <form id="promise" data-kind="PROMISE" autocomplete="off">
    <label for="promisedFor">${esc(t.payDate)}</label>
    <input id="promisedFor" name="promisedFor" type="date" required>
    <label for="payerName2">${esc(t.yourName)}</label>
    <input id="payerName2" name="payerName" maxlength="80">
    <div class="btns"><button class="primary" type="submit">${esc(t.send)}</button></div>
    <div class="msg" role="status"></div>
  </form>
</div>`
    : '';

  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<meta property="og:title" content="${esc(t.statement)} - ${esc(view.business.name)}">
<title>${esc(t.statement)} - ${esc(view.business.name)}</title>
<style>${CSS}</style>
</head>
<body>
<div class="wrap">
  <div class="top">
    <div class="shop">${view.business.logo ? `<img src="${esc(view.business.logo)}" alt="">` : ''}<b>${esc(view.business.name)}</b></div>
    <a class="lang" href="${base}?lang=${other}">${esc(t.language)}</a>
  </div>

  <div class="hero">
    <small>${esc(t.statementFor)} ${esc(view.debtor.name)} · ${esc(t.asOf)} ${esc(formatDate(view.asOf, lang))}</small>
    <div class="owed ${owed ? '' : 'clear'}">${owed ? esc(formatKes(view.outstanding)) : esc(t.nothingOwed)}</div>
    ${owed ? `<small>${esc(t.youOwe)}</small>` : ''}
    ${view.overdue > 0 ? `<span class="pill">${esc(t.overdue)}: ${esc(formatKes(view.overdue))}</span>` : ''}
    ${view.message ? `<div class="note">${esc(view.message)}</div>` : ''}
  </div>

  ${items ? `<h2>${esc(t.openItems)}</h2>${items}` : ''}

  ${owed && view.business.payInstructions ? `<h2>${esc(t.howToPay)}</h2><div class="card pay">${esc(view.business.payInstructions)}</div>` : ''}

  ${claims}

  <div class="btns"><a class="btn ghost" href="${base}/pdf?lang=${lang}">${esc(t.download)}</a></div>

  ${payments ? `<h2>${esc(t.recentPayments)}</h2>${payments}` : ''}

  ${view.business.phone ? `<div class="foot">${esc(t.contact)} ${esc(view.business.phone)}</div>` : ''}

  <div class="join">
    <h3>${esc(t.joinTitle)}</h3>
    <p>${esc(t.joinBody(view.business.name, view.inviteCode))}</p>
    <a class="btn" href="${esc(options.appDownloadPath)}">${esc(t.getApp)}</a>
  </div>
  <div class="foot">${esc(t.preparedWith)}</div>
</div>
<script nonce="${esc(nonce)}">${SCRIPT}</script>
</body>
</html>`;
}

export function renderExpiredPage(lang: Lang, nonce?: string): string {
  const t = stringsFor(lang);
  void nonce;
  return `<!doctype html>
<html lang="${lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title>${esc(t.expired)}</title>
<style>${CSS}</style></head>
<body><div class="wrap"><div class="hero"><div class="owed" style="font-size:24px">${esc(t.expired)}</div>
<p class="sub">${esc(t.expiredHelp)}</p></div></div></body></html>`;
}

/** pdfmake document definition for the same statement. Helvetica only (no font files to ship). */
export function buildStatementPdf(view: StatementView, lang: Lang): Record<string, unknown> {
  const t = stringsFor(lang);
  const dash = (d: Date | null) => (d ? formatDate(d, lang) : '');

  const itemRows = view.items.map((item) => [
    { text: formatDate(item.date, lang) },
    { text: [{ text: item.reference, bold: true }, item.description ? `\n${item.description}` : ''] },
    { text: formatKes(item.original), alignment: 'right' },
    { text: formatKes(item.paid), alignment: 'right' },
    { text: formatKes(item.outstanding), alignment: 'right', bold: true },
    {
      text: item.dueDate ? (item.overdueDays > 0 ? t.overdueBy(item.overdueDays) : dash(item.dueDate)) : '',
      color: item.overdueDays > 0 ? DANGER : INK,
    },
  ]);

  const content: unknown[] = [
    {
      columns: [
        [
          { text: view.business.name, fontSize: 18, bold: true, color: BRAND },
          view.business.phone ? { text: view.business.phone, color: MUTED, margin: [0, 2, 0, 0] } : '',
        ],
        {
          text: [
            { text: `${t.statement}\n`, fontSize: 14, bold: true },
            { text: `${t.asOf} ${formatDate(view.asOf, lang)}`, color: MUTED },
          ],
          alignment: 'right',
        },
      ],
      margin: [0, 0, 0, 14],
    },
    {
      table: {
        widths: ['*', 'auto'],
        body: [
          [
            {
              stack: [
                { text: t.statementFor, color: MUTED, fontSize: 9 },
                { text: view.debtor.name, fontSize: 14, bold: true },
              ],
              fillColor: BRAND_SOFT,
              margin: [10, 8, 10, 8],
            },
            {
              stack: [
                { text: t.youOwe, color: MUTED, fontSize: 9, alignment: 'right' },
                {
                  text: formatKes(view.outstanding),
                  fontSize: 18,
                  bold: true,
                  alignment: 'right',
                  color: view.outstanding > 0 ? INK : OK,
                },
                view.overdue > 0
                  ? { text: `${t.overdue}: ${formatKes(view.overdue)}`, color: DANGER, alignment: 'right', fontSize: 9 }
                  : '',
              ],
              fillColor: BRAND_SOFT,
              margin: [10, 8, 10, 8],
            },
          ],
        ],
      },
      layout: 'noBorders',
      margin: [0, 0, 0, 12],
    },
  ];

  if (view.message) content.push({ text: view.message, italics: true, margin: [0, 0, 0, 10] });

  if (itemRows.length) {
    content.push({
      table: {
        headerRows: 1,
        widths: [58, '*', 58, 52, 62, 62],
        body: [
          [t.date, t.receipt, t.original, t.paidSoFar, t.balance, t.due].map((h, i) => ({
            text: h,
            bold: true,
            fillColor: '#F3F4F6',
            alignment: i >= 2 && i <= 4 ? 'right' : 'left',
          })),
          ...itemRows,
        ],
      },
      layout: {
        hLineWidth: () => 0.5,
        vLineWidth: () => 0,
        hLineColor: () => LINE,
        paddingTop: () => 5,
        paddingBottom: () => 5,
      },
    });
  } else {
    content.push({ text: t.nothingOwed, color: OK, bold: true, margin: [0, 6, 0, 0] });
  }

  if (view.outstanding > 0 && view.business.payInstructions) {
    content.push({ text: t.howToPay, bold: true, fontSize: 11, margin: [0, 16, 0, 4] });
    content.push({ text: view.business.payInstructions, margin: [0, 0, 0, 4] });
  }

  if (view.payments.length) {
    content.push({ text: t.recentPayments, bold: true, fontSize: 11, margin: [0, 16, 0, 4] });
    content.push({
      table: {
        widths: ['*', 'auto', 'auto'],
        body: view.payments.map((p) => [
          formatDate(p.date, lang),
          `${(t.method as Record<string, string>)[p.method] ?? p.method}${p.reference ? ` ${p.reference}` : ''}`,
          { text: formatKes(p.amount), alignment: 'right', color: OK },
        ]),
      },
      layout: { hLineWidth: () => 0.5, vLineWidth: () => 0, hLineColor: () => LINE },
    });
  }

  return {
    content,
    defaultStyle: { font: 'Helvetica', fontSize: 9, color: INK },
    pageMargins: [36, 36, 36, 48],
    footer: (page: number, pages: number) => ({
      columns: [
        { text: t.pdfFooter, color: MUTED, fontSize: 8, margin: [36, 0, 0, 0] },
        { text: `${page} / ${pages}`, alignment: 'right', color: MUTED, fontSize: 8, margin: [0, 0, 36, 0] },
      ],
      margin: [0, 14, 0, 0],
    }),
  };
}
