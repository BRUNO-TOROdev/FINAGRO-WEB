import ExcelJS from "exceljs";

export type ImportSourceRow={source_row_number:number;issue_date:string;due_date:string;group:string;subgroup:string;document_number:string;document_name:string;client:string;description:string;payment_method:string;producer:string;farm:string;bank:string;bank_account:string;amount:string;status:string;season:string;direction:string};
const text=(value:unknown)=>value===null||value===undefined?"":String(typeof value==="object"&&value&&"text" in value?(value as {text:string}).text:value).trim();
const date=(value:unknown)=>value instanceof Date?value.toISOString().slice(0,10):text(value).slice(0,10);
const money=(value:unknown)=>{
 if(typeof value==="number")return String(value);
 const raw=text(value).replace(/^R\$\s*/,"").replace(/\s/g,"");
 return raw.includes(",")?raw.replaceAll(".","").replace(",","."):raw;
};

export async function parseFinagroWorkbook(buffer:ArrayBuffer,start:string,end:string){
 const workbook=new ExcelJS.Workbook();await workbook.xlsx.load(buffer);const sheet=workbook.getWorksheet("Base de Dados");if(!sheet)throw new Error("FINAGRO_BASE_SHEET_NOT_FOUND");const rows:ImportSourceRow[]=[];
 sheet.eachRow((row,rowNumber)=>{if(rowNumber<7)return;const issue=date(row.getCell(2).value);if(!issue||issue<start||issue>end)return;rows.push({source_row_number:rowNumber,issue_date:issue,due_date:date(row.getCell(3).value),group:text(row.getCell(4).value),subgroup:text(row.getCell(5).value),document_number:text(row.getCell(6).value),document_name:text(row.getCell(7).value),client:text(row.getCell(8).value),description:text(row.getCell(9).value),payment_method:text(row.getCell(10).value),producer:text(row.getCell(11).value),farm:text(row.getCell(12).value),bank:text(row.getCell(13).value),bank_account:text(row.getCell(14).value),amount:money(row.getCell(15).value),status:text(row.getCell(16).value),season:text(row.getCell(17).value),direction:text(row.getCell(18).value)});});return rows;
}
