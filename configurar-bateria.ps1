#Requires -RunAsAdministrator
# Ajustes do plano de energia que valem SO na bateria (DC). Na tomada (AC) nada muda.
# Rodar uma vez. Para desfazer: powercfg -restoredefaultschemes

function Set-DC($sub, $setting, $value, $nome) {
    powercfg /setdcvalueindex SCHEME_CURRENT $sub $setting $value
    if ($LASTEXITCODE -eq 0) { Write-Host "OK   $nome = $value" } else { Write-Warning "FALHOU $nome" }
}

# Mostra no painel de energia as opcoes que vem escondidas
powercfg -attributes SUB_PROCESSOR PROCFREQMAX -ATTRIB_HIDE

# Item 2: boost desligado na bateria + EPP 90 + Core Parking ativo + AMD Power Slider/PowerPlay + iGPU
Set-DC SUB_PROCESSOR PROCTHROTTLEMIN 5   'Estado minimo do processador (%)'
Set-DC SUB_PROCESSOR PROCTHROTTLEMAX 100 'Estado maximo do processador (%)'
Set-DC SUB_PROCESSOR PERFBOOSTMODE   0   'Modo de boost (0 = desligado)'
Set-DC SUB_PROCESSOR PERFEPP         90  'Preferencia de eficiencia (EPP 90)'
Set-DC SUB_PROCESSOR 0cc5b647-c1df-4637-891a-dec35c318583 5 'Core Parking minimo (%)'

# GPU integrada forcada + AMD SMU/PowerPlay em economia
Set-DC c763b4ec-0e50-4b6b-9bed-2b92a6ee884e 7ec1751b-60ed-4588-afb5-9819d3d77d90 0 'AMD Power Slider (Economia)'
Set-DC f693fb01-e858-4f00-b20f-f30e12ac06d6 191f65b5-d45c-4a4f-8aae-1ab8bfd980e6 0 'AMD PowerPlay (Otimizar bateria)'
Set-DC 5fb4938d-1ee8-4b0f-9a3c-5036b0ab995c dd848b2a-8a5d-4451-9ae2-39cd41658f6c 1 'Preferencia GPU (Baixo consumo / iGPU)'
Set-DC e276e160-7cb0-43c6-b20b-73f5dce39954 a1662ab2-9d34-4e53-ba8b-2639b9e20857 0 'Graficos Alternaveis (Forcar iGPU)'

# Economia de Energia do Windows automatica na bateria + JS/Video/NVMe
Set-DC de830923-a562-41af-a086-e3a2c6bad2da e69653ca-cf7f-4f05-aa73-cb833fa90ad4 100 'Economia de Energia automatica (%)'
Set-DC 02f815b5-a5cf-4c84-bf20-649d1f75d3d8 4c793e7d-a264-42e1-87d3-7a0d2f523ccd 0   'JS Timer (Economia maxima)'
Set-DC 9596fb26-9850-41fd-ac3e-f7c3c00afd4b 34c7b99f-9a6d-4b3c-8dc7-b6693b78cef4 2   'Video (Economia de energia)'
Set-DC 0012ee47-9041-4b5d-9b77-535fba8b1442 0b2d69d7-a2a1-449c-9680-f91c70521c60 2   'AHCI (HIPM+DIPM)'
Set-DC 0012ee47-9041-4b5d-9b77-535fba8b1442 fc7372b6-ab2d-43ee-8797-15e9841f2cca 1   'NVMe NOPPME'

# Item 3: brilho padrao na bateria
Set-DC SUB_VIDEO aded5e82-b909-4619-9949-f5d71dac0bcb 30 'Brilho na bateria (%)'

# PCIe ASPM = 1 (Moderada: permite GTX 1650 dormir em D3); Wi-Fi em 0 para nao estourar audio (DPC)
Set-DC SUB_PCIEXPRESS ASPM 1 'PCIe ASPM Moderada'
Set-DC 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 'Wi-Fi desempenho maximo'

powercfg /setactive SCHEME_CURRENT
Write-Host ''
Write-Host 'Plano atualizado. A tela em 60 Hz e o fechamento de apps ficam no modo.ps1.'
