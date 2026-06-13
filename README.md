[![Open in Visual Studio Code](https://classroom.github.com/assets/open-in-vscode-2e0aaae1b6195c2367325f4f02e2d04e9abb55f0b24a779b69b11b9e10269abc.svg)](https://classroom.github.com/online_ide?assignment_repo_id=24078969&assignment_repo_type=AssignmentRepo)
<h1 align="center">Visualización usando pantalla LCD 16x2</h1>

# Integrantes


# Informe

Indice:

1. [Diseño implementado](#diseño-implementado)
2. [Simulaciones](#simulaciones)
3. [Implementación](#implementación)
4. [Conclusiones](#conclusiones)
5. [Referencias](#referencias)

## Diseño implementado
### Descripción
El laboratorio consiste en controlar una pantalla LCD 16×2 desde la tarjeta Altera Cyclone IV 
usando el protocolo I2C, implementando la lógica de control mediante una Máquina de Estados 
Finita (FSM) descrita en Verilog.

La comunicación se realiza a través del módulo adaptador PCF8574 (dirección I2C 0x27), que 
convierte la interfaz paralela del LCD en una interfaz de 2 hilos (SDA/SCL), reduciendo el 
número de pines requeridos en la FPGA. El LCD opera en modo 4 bits, por lo que cada byte 
enviado al controlador HD44780 se divide en dos nibbles, pulsando la señal EN en cada uno.

El sistema se compone de dos módulos principales:

- **i2c_send**: implementa el maestro I2C. Recibe un byte de 8 bits y lo transmite al esclavo 
siguiendo la secuencia START → ADDR → ACK → DATA → ACK → STOP.
- **top**: implementa la FSM de control del LCD. Coordina la inicialización del display, 
la escritura del texto en memoria DDRAM y el efecto de scroll horizontal continuo.
### Diagramas


**FSM — Módulo i2c_send**

El módulo i2c_send es una FSM de 8 estados que genera las señales SCL y SDA del protocolo I2C:

| Estado | Descripción | Transición |
|---|---|---|
| IDLE | Espera señal send. SCL y SDA en alto. | send=1 → START |
| START | Genera condición START: SDA baja con SCL en alto. | Automático → ADDR |
| ADDR | Transmite 7 bits de dirección (0x27) + bit W=0. | bit_cnt=0 → ACK1 |
| ACK1 | Libera SDA y espera ACK del esclavo. | Automático → DATA |
| DATA | Transmite los 8 bits del byte de dato. | bit_cnt=0 → ACK2 |
| ACK2 | Libera SDA y espera ACK del esclavo. | Automático → STOP |
| STOP | Genera condición STOP: SDA sube con SCL en alto. | Automático → DONE |
| DONE | Activa done=1 por un ciclo y regresa a IDLE. | Automático → IDLE |

Cada bit se genera dividiendo el reloj en 4 fases de 124 ciclos, produciendo una frecuencia 
I2C de aproximadamente 100 kHz (modo estándar).

**FSM — Módulo top**

El módulo top controla la secuencia completa de operación del LCD mediante 14 estados:

| Estado | Nombre | Descripción |
|---|---|---|
| S0 | S_WAIT_INIT | Espera 50 ms tras encendido antes de iniciar. |
| S1 | S_INIT | Envía un byte de la secuencia de inicialización (28 bytes en total). |
| S2 | S_INIT_WAIT | Espera done del i2c_send. |
| S3 | S_INIT_DELAY | Delay entre bytes de init. Delay largo tras el comando Display Clear. |
| S4 | S_HOME | Envía comando Cursor Home (4 bytes I2C). |
| S5 | S_HOME_WAIT | Espera done. Al completar los 4 bytes pasa a escritura. |
| S6 | S_WRITE | Envía un nibble de cada carácter del texto (4 bytes por carácter). |
| S7 | S_WRITE_WAIT | Espera done del byte enviado. |
| S8 | S_WRITE_DELAY | Delay entre bytes. Avanza nibble/carácter o pasa a scroll. |
| S9 | S_SHIFT_WAIT | Delay entre shifts, controla la velocidad del scroll. |
| S10 | S_SHIFT | Envía un byte del comando Shift Display Left. |
| S11 | S_SHIFT_BYTE_WAIT | Espera done. Al completar 4 bytes vuelve a S_SHIFT_WAIT. |
| S12 | S_HOME2 | Cursor home para reiniciar posición del display. |
| S13 | S_HOME2_WAIT | Espera done y reinicia el contador de shifts. |


## Simulaciones 

<!-- (Incluir las de Digital si hicieron uso de esta herramienta, pero también deben incluir simulaciones realizadas usando un simulador HDL como por ejemplo Icarus Verilog + GTKwave) -->


## Implementación
El diseño fue implementado en la tarjeta Altera Cyclone IV EP4CE6E22C8. Los pasos seguidos 
fueron:

1. Configuración del Pin Planner en Quartus según la tabla de pines de la tarjeta.
2. Reasignación del pin 101 (nCEO) como I/O regular en Assignments → Device → 
Device and Pin Options → Dual-Purpose Pins.
3. Conexión de la pantalla LCD 16×2 al header correspondiente, alineando el pin 1 
de la pantalla con el pin 1 marcado en la PCB.
4. Programación de la tarjeta y verificación del funcionamiento.

El sistema funcionó correctamente. La pantalla inicializó sin errores y mostró el mensaje 
configurado. En la siguiente imagen se puede observar el prototipo en funcionamiento, donde 
la LCD despliega el mensaje "Configura alarma" en la primera línea y la hora actual 
"11:26:32" en la segunda, evidenciando la correcta lectura del módulo RTC DS3231 y la 
comunicación I2C con la pantalla:

## Conclusiones
La FSM implementada en Verilog permite gestionar de forma determinista la secuencia de 
comandos requerida por el controlador HD44780, demostrando la ventaja del diseño en hardware 
para aplicaciones con requisitos de temporización precisos.

- El módulo i2c_send implementado desde cero en la FPGA verificó el funcionamiento correcto 
del protocolo I2C, generando una frecuencia de reloj de aproximadamente 100 kHz compatible 
con el modo estándar.

- El modo de operación de 4 bits del LCD combinado con el adaptador PCF8574 reduce el 
consumo de pines de la FPGA de 8 a 2, siendo una solución eficiente directamente aplicable 
al proyecto del pastillero programable.

- Los módulos desarrollados, en particular i2c_send y la lógica de control LCD, son 
componentes reutilizables en el proyecto final del pastillero, donde la misma pantalla 
comparte el bus I2C con el módulo RTC DS3231 para mostrar la hora actual y los mensajes 
de alarma.

## Referencias
- Hitachi Semiconductor. (2000). HD44780U Dot Matrix LCD Controller/Driver. Hitachi Ltd.
- NXP Semiconductors. (2014). PCF8574 Remote 8-bit I/O expander for I2C-bus. NXP Semiconductors.
- Eslava, S. (2025). Máquinas de estados finitos FSM [Diapositivas de clase]. Universidad Nacional de Colombia.
- Eslava, S. (2025). Nivel de transferencia de datos RTL [Diapositivas de clase]. Universidad Nacional de Colombia.
- Intel Corporation. (2020). Cyclone IV Device Handbook. Intel FPGA.
