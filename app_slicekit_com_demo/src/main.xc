// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

/*===========================================================================
 Filename: main.xc
 Project : app_slicekit_com_demo
 Author : XMOS Ltd
 Version : 1v0
 Purpose : This file implements demostration of comport, LED's
  	  	   and ADC using GPIO slice
 -----------------------------------------------------------------------------

 ===========================================================================*/

/*---------------------------------------------------------------------------
 include files
 ---------------------------------------------------------------------------*/
#include <xs1.h>
#include <platform.h>
#include "uart_rx.h"
#include "uart_tx.h"
#include <print.h>
#include<i2c.h>
#include<string.h>
#include<common.h>

//#define AD7995_0 //define this in module_i2c_master

/*---------------------------------------------------------------------------
 ports and clocks
 ---------------------------------------------------------------------------*/
#define CORE_NUM 1
#define BUTTON_PRESS_VALUE 14
on stdcore[CORE_NUM] : buffered in port:1 p_rx =  PORT_ETH_TXCLK_2;
on stdcore[CORE_NUM] : out port p_tx = PORT_ETH_RXDV_2;
on stdcore[CORE_NUM]: port p_led=PORT_ETH_RXD_2;
on stdcore[CORE_NUM]: in port p_button1=PORT_ETH_MDIOC_2;
struct r_i2c i2cOne = {
		PORT_ETH_TXEN_2,
		PORT_ETH_RXCLK_2,
		1000
 };


/*---------------------------------------------------------------------------
 typedefs
 ---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------
 global variables
 ---------------------------------------------------------------------------*/
#define ARRAY_SIZE(x) (sizeof(x)/sizeof(x[0]))
unsigned char tx_buffer[64];
unsigned char rx_buffer[64];
#pragma unsafe arrays
/*---------------------------------------------------------------------------
 static variables
 ---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------
 implementation
 ---------------------------------------------------------------------------*/

void dummy()
{
	while (1);
}



/**
 * Top level main for multi-UART demonstration
 */
int main()
{
  chan c_chanTX, c_chanRX,c_receive,c_process,c_end;

	par
	{
    	on stdcore[CORE_NUM] : uart_rx(p_rx, rx_buffer, ARRAY_SIZE(rx_buffer), BAUD_RATE, 8, UART_TX_PARITY_EVEN, 1, c_chanRX);
    	on stdcore[CORE_NUM] : uart_tx(p_tx, tx_buffer, ARRAY_SIZE(tx_buffer), BAUD_RATE, 8, UART_TX_PARITY_EVEN, 1, c_chanTX);
    	on stdcore[CORE_NUM] : app_manager(c_chanTX,c_chanRX,c_process,c_end);
    	on stdcore[CORE_NUM] : process_data(c_process, c_end);
    	on stdcore[CORE_NUM]: dummy();
    	on stdcore[CORE_NUM]: dummy();
    	on stdcore[CORE_NUM]: dummy();
    	on stdcore[CORE_NUM]: dummy();
	}
  return 0;
}

/** =========================================================================
 * app_manager
 *
 * Polling uart RX and push button switches and send received commands to
 * process_data thread
 *
 * \param channel to uartTX thread, channel communication to uartRX thread and
 * channel communication to process data thread
 *
 * \return None
 *
 **/
void app_manager(chanend c_uartTX,chanend c_uartRX, chanend c_process, chanend c_end)
{
	unsigned char i2c_register[1]={0x13};
	int adc_value;
	timer t;
	unsigned char CONSOLE_MESSAGES[16][110]=
	{
	 "\r\nCOMMAND MODE ACTIVATED",
	 "\r\nEXIT COMMAND MODE\r\n",
	 "\r\nINVALID COMMAND - Use 'help' for details",
	 "\r\nCOMMAND EXECUTED",
	 "\r\nBUTTON x PRESSED",
	 "\r\nNO BUTTONS ARE PRESSED",
	 "\r\nWELCOME TO GPIO DEMO",
	 "\r\n setall \t- Sets all LEDs ON\r\n clearall \t- Clear all LEDs",
	 "\r\n setled 'N' \t- Switch ON LED N",
	 "\r\n help \t\t- Display all supported commands",
	 "\r\n chkbuttons \t- Returns if any buttons pressed since last 'chkbuttons' command",
	 "\r\n readadc \t- Read ADC vaue and Displays temperature\r\n\r\n 'N' is in range 1 to 4",
	 "\r\nCURRENT TEMPERATURE VALUE IS : ",
	 "\r\n(**ECHO DATA MODE ACTIVATED**)\r\nPress '>cmd' for command mode\r\n",
	 "\r\n\r\n-------------------------HELP--------------------------------",
	 "\r\n clearled 'N' \t- Switch OFF LED 'N'\r\n exit \t\t- Exit from Command mode"
	};
	unsigned char rcvbuffer;
	unsigned char cmd_rcvbuffer[20];
	unsigned char data_arr[1]={'K'};
	unsigned crc_value=0,data=0;
	unsigned byte,button_value1=0,button_value2=0,time,led_value=0x01;
	int j=0,skip=1,selection;
	int button, button1_press=0,button2_press=0;
	unsigned COMMAND_MODE=0;
	uart_rx_client_state rxState;
	unsigned char buffer;
	uart_rx_init(c_uartRX, rxState);
	uart_rx_set_baud_rate(c_uartRX, rxState, BAUD_RATE);

	uart_tx_set_baud_rate(c_uartTX, BAUD_RATE);
	t:>time;
	i2c_master_write_reg(0x28, 0x00, i2c_register, 1, i2cOne); //Configure ADC by writing the settings to register
	uart_tx_string(c_uartTX,CONSOLE_MESSAGES[6]); //Display Welcome messages on UART TX Pin
	uart_tx_string(c_uartTX,CONSOLE_MESSAGES[13]);
	uart_tx_send_byte(c_uartTX, '\r');
	uart_tx_send_byte(c_uartTX, '\n');
	 while(1)
	 {
		select
		{
			case c_end:>data:
				c_end:>data;
				if(data == BUTTON_1) //Cycle LEDs on button 1 press
				{
					printstrln("Button 1 Pressed");
					p_led<:(led_value);
					led_value=led_value<<1;
					if(led_value == 16)
					{
						led_value=0x01;
					}
				}
				if(data == BUTTON_2) //Displays Temperature on console if Button 2 is pressed
				{
					adc_value=read_adc_value();
					data_arr[0]=(linear_interpolation(adc_value));
					printstr("Temperature is :");
					printint(linear_interpolation(adc_value));
					printstrln(" C");
				}
				break;
			case uart_rx_get_byte_byref(c_uartRX, rxState, buffer):

				if(buffer == '>') //IUF received data is '>' character then expects cmd to endter into command mode
				{
					j=0;
					uart_rx_get_byte_byref(c_uartRX, rxState, buffer);
					cmd_rcvbuffer[j]=buffer;
					if((cmd_rcvbuffer[j] == 'C' )|| (cmd_rcvbuffer[j] =='c')) //Checks if received data is 'C' or 'c'
					{
						j++;
						uart_rx_get_byte_byref(c_uartRX, rxState, buffer);
						cmd_rcvbuffer[j]=buffer;

						if((cmd_rcvbuffer[j] == 'm' )|| (cmd_rcvbuffer[j] =='M')) //Checks if received data is 'M' or 'm'
						{
							j++;
							uart_rx_get_byte_byref(c_uartRX, rxState, buffer);
							cmd_rcvbuffer[j]=buffer;
							if((cmd_rcvbuffer[j] == 'D' )|| (cmd_rcvbuffer[j] =='d'))//Checks if received data is 'D' or 'd'
							{
								uart_tx_send_byte(c_uartTX, '\r');
								uart_tx_send_byte(c_uartTX, '\n');
								uart_tx_string(c_uartTX,CONSOLE_MESSAGES[0]);
								COMMAND_MODE=1; //activates command mode as received data is '>cmd'
								uart_tx_send_byte(c_uartTX, '\r');
								uart_tx_send_byte(c_uartTX, '\n');
								uart_tx_send_byte(c_uartTX, '>'); //displays '>' if command mode is activated
							}
							else
							{
								uart_tx_send_byte(c_uartTX, '>');
								for(int i=0;i<3;i++)
									uart_tx_send_byte(c_uartTX, cmd_rcvbuffer[i]); // if received dta is not 'c' displays back the received data
							}
						}
						else
						{
							uart_tx_send_byte(c_uartTX, '>'); //if received data is not 'm' displays the received data
							for(int i=0;i<2;i++)
								uart_tx_send_byte(c_uartTX, cmd_rcvbuffer[i]);
						}
					}
					else
					{
						uart_tx_send_byte(c_uartTX, '>');
						uart_tx_send_byte(c_uartTX, cmd_rcvbuffer[j]);
						j=0;
					}
				}
				else
				{
					uart_tx_send_byte(c_uartTX,buffer); //Echoes back the input characters if not in command mode
				}
				while(COMMAND_MODE) //Command mode activated
				{
					j=0;
					skip=1;
					while(skip == 1)
					{
						select
						{
							case uart_rx_get_byte_byref(c_uartRX, rxState, buffer):
								cmd_rcvbuffer[j]=buffer;
								if(cmd_rcvbuffer[j++] == '\r')
								{
									skip=0;
									j=0;
									while(cmd_rcvbuffer[j] != '\r')
									{
										c_process<:cmd_rcvbuffer[j]; //received valid command and send the command to the process_data theread
										uart_tx_send_byte(c_uartTX, cmd_rcvbuffer[j]);
										j++;
									}
									cmd_rcvbuffer[j]='\0';
									c_process<:cmd_rcvbuffer[j];
									for(int inc=0;inc<20;inc++) //Clears the command buffer
										cmd_rcvbuffer[inc]='0';
									j=0;
								}
								break;
							case c_end:>data:
								if(data!=EXIT && data!=INVALID )
								{
									uart_tx_string(c_uartTX,CONSOLE_MESSAGES[3]); //Displays COmmand Executed Message on Uart
								}

								switch(data)
								{
									case EXIT: //Exit from command mode
										COMMAND_MODE=0;
										skip=0;
										uart_tx_string(c_uartTX,CONSOLE_MESSAGES[1]);
										uart_tx_string(c_uartTX,CONSOLE_MESSAGES[13]);
										break;

									case SET_LED_1: //Read port Value and Set LED 1 ON
										p_led:>data;
										data=data | 0x01;
										p_led<:data;
										break;

									case CLEAR_LED_1://Read port Value and Set LED 1 OFF
										p_led:>data;
										p_led<:data&0x0E;
										break;

									case SET_LED_2: //Read port Value and Set LED 2 ON
										p_led:>data;
										p_led<:data | 0x02;
										break;

									case CLEAR_LED_2: //Read port Value and Set LED 2 OFF
										p_led:>data;
										p_led<:data&0x0D;

										break;

									case SET_LED_3: //Read port Value and Set LED 3 ON
										p_led:>data;
										p_led<:data | 0x04;
										break;

									case CLEAR_LED_3: //Read port Value and Set LED 3 OFF
										p_led:>data;
										p_led<:data&0x0B;
										break;

									case SET_LED_4: //Read port Value and Set LED 4 ON
										p_led:>data;
										p_led<:data | 0x08;
										break;

									case CLEAR_LED_4: //Read port Value and Set LED 4 OFF
										p_led:>data;
										p_led<:data&0x07;

										break;

									case CLEAR_ALL: //sets all four LEDs OFF
										p_led<:0;
										break;

									case SET_ALL: //sets all four LEDs ON
										p_led<:0x0F;
										break;

									case BUTTON_PRESSED: //Checks if button is pressed
										c_end:>button;
										if(button == BUTTON_1) //Prints Button 1 is pressed on the Uart
										{
											CONSOLE_MESSAGES[4][9]='1';
											uart_tx_string(c_uartTX,CONSOLE_MESSAGES[4]);
											button1_press=1;
										}
										if(button == BUTTON_2) //Prints Button 2 is pressed on Uart
										{
											CONSOLE_MESSAGES[4][9]='2';
											uart_tx_string(c_uartTX,CONSOLE_MESSAGES[4]);
											button2_press=1;
										}
										break;
									case HELP: //Displays help messages on Uart
										uart_tx_string(c_uartTX,CONSOLE_MESSAGES[14]);
										uart_tx_string(c_uartTX,CONSOLE_MESSAGES[7]);
										uart_tx_string(c_uartTX,CONSOLE_MESSAGES[8]);
										uart_tx_string(c_uartTX,CONSOLE_MESSAGES[9]);
										uart_tx_string(c_uartTX,CONSOLE_MESSAGES[10]);
										uart_tx_string(c_uartTX,CONSOLE_MESSAGES[15]);
										uart_tx_string(c_uartTX,CONSOLE_MESSAGES[11]);
										uart_tx_send_byte(c_uartTX, '\r');
										uart_tx_send_byte(c_uartTX, '\n');
										break;
									case READ_ADC: //Displays temperature value on the Uart
										adc_value=read_adc_value();
										data_arr[0]=(linear_interpolation(adc_value));
										uart_tx_string(c_uartTX,CONSOLE_MESSAGES[12]);
										uart_tx_send_byte(c_uartTX, (data_arr[0]/10)+'0');
										uart_tx_send_byte(c_uartTX, (data_arr[0]%10)+'0');
										uart_tx_send_byte(c_uartTX, 32);
										uart_tx_send_byte(c_uartTX, 'C');
										break;
									case INVALID: //Displays command input is invalid command on the Uart
										uart_tx_string(c_uartTX,CONSOLE_MESSAGES[2]);
										break;
									case CHK_BUTTONS: //Checks if button are pressed and displays on the Uart
										if(button1_press)
										{
											CONSOLE_MESSAGES[4][9]='1';
											uart_tx_string(c_uartTX,CONSOLE_MESSAGES[4]); //Displays Button 1 is pressed
										}
										if(button2_press)
										{
											CONSOLE_MESSAGES[4][9]='2';
											uart_tx_string(c_uartTX,CONSOLE_MESSAGES[4]); //Dipslays Button 2 is pressed
										}
										if( !button1_press && !button2_press)
										{
											uart_tx_string(c_uartTX,CONSOLE_MESSAGES[5]); //Displays No Buttons are pressed
										}
										button1_press=0;
										button2_press=0;
								}
								if(data != EXIT) //Exits from command mode
								{
									uart_tx_send_byte(c_uartTX, '\r');
									uart_tx_send_byte(c_uartTX, '\n');
									uart_tx_send_byte(c_uartTX, '>');
								}
								break;
						}//select
					}//skip
					j=0;
				}//command mode
				break;
		}//main select
	 }//superloop
}//thread

/** =========================================================================
 * process data
 *
 * process received data to see if received data is valid command or not
 *
 * \param channel communication to app manager thread and
 *
 * \return None
 *
 **/
void process_data(chanend c_process, chanend c_end)
{
	int k=0,skip=1,i=0;
	unsigned data=0,button_value1,button_value2;
	unsigned char cmd_rcvbuffer[20];
	int button=1,button1_pressed=0,button2_pressed=0;
	timer t;
	unsigned time;

	t:>time;
	p_button1:>button_value1;
	while(1)
	{
		select
		{
			case button => p_button1 when pinsneq(button_value1):>button_value1:
				button=0;
				break;

			case !button => t when timerafter(time+20000000):>time: //Read button values for every 200 ms
				p_button1:> button_value1;
			//checks if button 1 is pressed or button 2 is pressed
				if(button_value1 == BUTTON_PRESS_VALUE)
				{
					button1_pressed=1;
					c_end<:BUTTON_PRESSED; //send button pressed command
					c_end<:BUTTON_1; //indicates button 1 is pressed
				}
				if(button_value1 == BUTTON_PRESS_VALUE-1)
				{
					button2_pressed=1;
					c_end<:BUTTON_PRESSED; //send button pressed command
					c_end<:BUTTON_2; //send button 2 is pressed

				}
				button=1;
				break;

			case c_process:>cmd_rcvbuffer[i++]:
				skip=1;
				while(skip == 1)
				{
					c_process:>cmd_rcvbuffer[i];
					if(cmd_rcvbuffer[i++] == '\0') //Reveived the command from  app_manager thread
						skip=0;
				}
				//Checks if received command is valid command or not and sends state machine value to app manager thread
				if(!strcmp(cmd_rcvbuffer,"exit"))
				{
					c_end<:EXIT;
				}
				else if(!strcmp(cmd_rcvbuffer,"setled 1"))
				{
					c_end<:SET_LED_1;
				}
				else if(!strcmp(cmd_rcvbuffer,"clearled 1"))
				{
					c_end<:CLEAR_LED_1;
				}
				else if(!strcmp(cmd_rcvbuffer,"setled 2"))
				{
					c_end<:SET_LED_2;
				}
				else if(!strcmp(cmd_rcvbuffer,"clearled 2"))
				{
					c_end<:CLEAR_LED_2;
				}
				else if(!strcmp(cmd_rcvbuffer,"setled 3"))
				{
					c_end<:SET_LED_3;
				}
				else if(!strcmp(cmd_rcvbuffer,"clearled 3"))
				{
					c_end<:CLEAR_LED_3;
				}
				else if(!strcmp(cmd_rcvbuffer,"setled 4"))
				{
					c_end<:SET_LED_4;
				}
				else if(!strcmp(cmd_rcvbuffer,"clearled 4"))
				{
					c_end<:CLEAR_LED_4;
				}
				else if(!strcmp(cmd_rcvbuffer,"clearall"))
				{
					c_end<:CLEAR_ALL;
				}
				else if(!strcmp(cmd_rcvbuffer,"setall"))
				{
					c_end<:SET_ALL;
				}
				else if(!strcmp(cmd_rcvbuffer,"chkbuttons"))
				{
					c_end<:CHK_BUTTONS;
				}
				else if(!strcmp(cmd_rcvbuffer,"help"))
				{
					c_end<:HELP;
				}
				else if(!strcmp(cmd_rcvbuffer,"readadc"))
				{
					c_end<:READ_ADC;
				}
				else
				{
					c_end<:INVALID;
				}
				i=0;
				for(int inc=0;inc<20;inc++)
					cmd_rcvbuffer[inc]='0'; //Clear command reveive buffer
				break;

		}
	}
}

/** =========================================================================
 * linear interpolation
 *
 * calculates temperatue basedd on linear interpolation
 *
 * \param int adc value
 *
 * \return int temperature
 *
 **/
int linear_interpolation(int adc_value)
{
	int i=0,x1,y1,x2,y2,temper;
	while(adc_value<TEMPERATURE_LUT[i][1])
	{
		i++;
	}
	//Calculating Linear interpolation using the formula y=y1+(x-x1)*(y2-y1)/(x2-x1)
	x1=TEMPERATURE_LUT[i-1][1];
	y1=TEMPERATURE_LUT[i-1][0];
	x2=TEMPERATURE_LUT[i][1];
	y2=TEMPERATURE_LUT[i][0];
	temper=y1+(((adc_value-x1)*(y2-y1))/(x2-x1)); //Calculate temeperature valus using linear interploation technique
	return temper;//Return Temperature value
}

/** =========================================================================
 * uart transmit string
 *
 * Transmits byte by byte to the UART TX thread for an input string
 *
 * \param usinged char message buffer
 *
 * \return None
 *
 **/
void uart_tx_string(chanend c_uartTX,unsigned char message[100]) //transmit string on Uart TX terminal
{
	int i=0;
	while(message[i]!='\0')
	{
		uart_tx_send_byte(c_uartTX,message[i]); //send data to uart byte by byte
		i++;
	}
}

/** =========================================================================
 * Read ADC value
 *
 * Read ADC value using I2C
 *
 * \param None
 *
 * \return int adc value
 *
 **/
int read_adc_value()
{
	int adc_value;
	unsigned char i2c_register1[2];
	i2c_master_rx(0x28, i2c_register1, 2, i2cOne); //Read value from ADC
	i2c_register1[0]=i2c_register1[0]&0x0F;
	adc_value=(i2c_register1[0]<<6)|(i2c_register1[1]>>2);
	return adc_value; //Return ADC value to the application
}
