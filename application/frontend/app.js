"use strict";

const INTERVALO_MS = 5000;

function formatarBytes(bytes) {
  const unidades = ["B", "KiB", "MiB", "GiB", "TiB"];
  let valor = bytes;
  let i = 0;
  while (valor >= 1024 && i < unidades.length - 1) {
    valor /= 1024;
    i += 1;
  }
  return valor.toFixed(i === 0 ? 0 : 1) + " " + unidades[i];
}

function formatarUptime(segundos) {
  const d = Math.floor(segundos / 86400);
  const h = Math.floor((segundos % 86400) / 3600);
  const m = Math.floor((segundos % 3600) / 60);
  return (d ? d + "d " : "") + h + "h " + m + "min";
}

// Preenche um <dl> usando textContent (nunca innerHTML) para evitar injecao de HTML.
function preencher(id, linhas) {
  const dl = document.getElementById(id);
  dl.replaceChildren();
  for (const [rotulo, valor] of linhas) {
    const dt = document.createElement("dt");
    const dd = document.createElement("dd");
    dt.textContent = rotulo;
    dd.textContent = valor === null || valor === undefined ? "indisponível" : String(valor);
    dl.append(dt, dd);
  }
}

function renderizar(s) {
  const i = s.instance;
  preencher("instancia", [
    ["ID da instância", i.instance_id],
    ["Tipo", i.instance_type],
    ["Zona de disponibilidade", i.availability_zone],
    ["IP privado", i.private_ip],
    ["IP público", i.public_ip],
    ["AMI", i.ami_id],
  ]);
  preencher("sistema", [
    ["Hostname", s.hostname],
    ["Sistema operacional", s.os],
    ["Kernel", s.kernel],
    ["Arquitetura", s.architecture],
    ["Python", s.python],
    ["Uptime", formatarUptime(s.uptime_seconds)],
  ]);
  preencher("recursos", [
    ["vCPUs", s.cpu_count],
    ["CPU em uso", s.cpu_percent + " %"],
    ["Load average (1/5/15 min)", [s.load_average["1m"], s.load_average["5m"], s.load_average["15m"]].map((n) => n.toFixed(2)).join(" / ")],
    ["Memória", formatarBytes(s.memory.used_bytes) + " de " + formatarBytes(s.memory.total_bytes) + " (" + s.memory.used_percent + " %)"],
    ["Disco /", formatarBytes(s.disk.used_bytes) + " de " + formatarBytes(s.disk.total_bytes) + " (" + s.disk.used_percent + " %)"],
  ]);
}

async function atualizar() {
  const estado = document.getElementById("estado");
  try {
    const resposta = await fetch("/api/status", { cache: "no-store" });
    if (!resposta.ok) {
      throw new Error("HTTP " + resposta.status);
    }
    renderizar(await resposta.json());
    estado.className = "";
    estado.textContent = "Atualizado em " + new Date().toLocaleTimeString("pt-BR");
  } catch (erro) {
    estado.className = "erro";
    estado.textContent = "Falha ao consultar /api/status: " + erro.message;
  }
}

atualizar();
setInterval(atualizar, INTERVALO_MS);
